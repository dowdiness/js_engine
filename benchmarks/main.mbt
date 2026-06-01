///|
/// CLI benchmark runner — secondary interface for CI baseline tracking.
///
/// This main function provides machine-readable output (CSV) and explicit
/// control over which benchmark categories run. It complements the native
/// @bench.T test blocks in benchmarks.mbt.
///
/// Usage:
///   moon run benchmarks --target js                       # regression only
///   moon run benchmarks --target js -- --all              # all categories
///   moon run benchmarks --target js -- --csv              # CSV output
///   moon run benchmarks --target js -- --startup-phases   # startup phase breakdown only
///   moon run benchmarks --target js -- --startup-new-interpreter-subphases
///                                                          # split new_interpreter startup
///   moon run benchmarks --target js -- --list             # list benchmarks with category/stage
///   moon run benchmarks --target js -- --all --csv        # full CSV snapshot
///
/// CSV output can be redirected to a file and committed as a performance
/// baseline:
///   moon run benchmarks --target js -- --all --csv > bench/baseline.csv
///
/// To compare two baselines:
///   diff bench/baseline.csv bench/current.csv
///
/// NOTE: Timing is only meaningful on the JS backend.
///       Other targets return 0.0 from now_ms() — see timer.*.mbt.
fn main {
  if timer_supported() == false {
    abort("benchmarks only produces meaningful results with --target js")
  }
  if has_startup_new_interpreter_subphases_arg() {
    let csv = has_csv_arg()
    if csv {
      print_csv_header()
    } else {
      println("=== js_engine new_interpreter startup subphases ===")
      println("Rows are independent microbenchmarks, not an additive profile.")
      println("")
    }
    try {
      for r in run_startup_new_interpreter_subphases() {
        if csv {
          print_result_csv(r)
        } else {
          print_result(r)
        }
      }
      if csv == false {
        println("")
        println(
          "Done. Re-run with --startup-new-interpreter-subphases --csv for CSV output.",
        )
      }
    } catch {
      e => {
        println("FATAL: benchmark failed: \{e}")
        abort("benchmark run failed")
      }
    }
    return
  }
  let args = parse_bench_args()
  if args.list_only {
    println("Available benchmarks (name, category, stage):")
    for pair in all_bench_names() {
      let (name, cat, stage) = pair
      println("  \{name}  [\{cat}/\{stage}]")
    }
    println("\nRun with --all to include component and workflow benchmarks.")
    println(
      "Run with --startup-new-interpreter-subphases for the focused new_interpreter split.",
    )
    return
  }
  if args.csv {
    print_csv_header()
  } else {
    println("=== js_engine Benchmark Suite (CLI runner) ===")
    println("Primary interface: moon test benchmarks/ --target js")
    println("")
    if args.startup_phases {
      println("Running startup phase breakdown only.")
      println(
        "Phase timings are independent microbenchmarks, not an additive profile.",
      )
    } else if args.run_all {
      println("Running all benchmarks (regression + component + workflow)...")
    } else {
      println("Running regression benchmarks only. Use --all for full suite.")
    }
    println("")
  }
  try {
    let results = if args.startup_phases {
      run_startup_phases()
    } else if args.run_all {
      run_all()
    } else {
      run_regression()
    }
    for r in results {
      if args.csv {
        print_result_csv(r)
      } else {
        print_result(r)
      }
    }
    if args.csv == false {
      println("")
      println("Done. Run with --all --csv to produce a full baseline snapshot.")
    }
  } catch {
    e => {
      println("FATAL: benchmark failed: \{e}")
      abort("benchmark run failed")
    }
  }
}
