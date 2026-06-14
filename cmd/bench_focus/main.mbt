///|
fn program_args(args : Array[String]) -> ArrayView[String] {
  if args.length() >= 1 {
    args[1:]
  } else {
    args[0:]
  }
}

///|
fn first_value(
  values : Map[String, Array[String]],
  key : String,
  default : String,
) -> String {
  match values.get(key) {
    Some(items) if items.length() > 0 => items[0]
    _ => default
  }
}

///|
fn optional_value(values : Map[String, Array[String]], key : String) -> String? {
  match values.get(key) {
    Some(items) if items.length() > 0 => Some(items[0])
    _ => None
  }
}

///|
fn flag_value(flags : Map[String, Bool], key : String) -> Bool {
  flags.get_or_default(key, false)
}

///|
fn parse_int_arg(raw : String, label : String) -> Int raise {
  @string.parse_int(raw) catch {
    _ => fail("error: " + label + " must be an integer")
  }
}

///|
fn exit_with_code(code : Int) -> Unit {
  if code != 0 {
    @sys.exit(code)
  }
}

///|
async fn main {
  let cmd = @argparse.Command(
    "bench-focus-mbt",
    flags=[
      @argparse.FlagArg(
        "fail-on-missing",
        about="exit non-zero if any selected row is absent from any run",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "runs",
        default_values=["5"],
        about="number of CSV snapshots to collect (default: 5)",
      ),
      @argparse.OptionArg(
        "rows",
        default_values=[@helpers.default_bench_rows().join(",")],
        about="comma-separated benchmark row names to summarize",
      ),
      @argparse.OptionArg(
        "command",
        default_values=[@helpers.DEFAULT_BENCH_COMMAND],
        about="benchmark command to run",
      ),
      @argparse.OptionArg(
        "output-root",
        default_values=["_build/bench-focus"],
        about="directory for timestamped raw CSV outputs",
      ),
      @argparse.OptionArg(
        "timestamp",
        about="output directory name override (default: UTC timestamp)",
      ),
    ],
    about=(
      #|Run the JS benchmark CSV command repeatedly and summarize selected rows
      #|with median/mean/range across runs. MoonBit shadow; Python remains authoritative.
    ),
  )
  let matches = cmd.parse(argv=program_args(@env.args()), env={}) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let rows = @helpers.row_names(first_value(matches.values, "rows", "")) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let runs = parse_int_arg(first_value(matches.values, "runs", "5"), "--runs") catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let config = @helpers.BenchConfig(
    runs~,
    rows~,
    command=first_value(
      matches.values,
      "command",
      @helpers.DEFAULT_BENCH_COMMAND,
    ),
    output_root=first_value(matches.values, "output-root", "_build/bench-focus"),
    timestamp=optional_value(matches.values, "timestamp"),
    fail_on_missing=flag_value(matches.flags, "fail-on-missing"),
  )
  let run = @helpers.run_bench_focus(config) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  if run.stdout != "" {
    @stdio.stdout.write(run.stdout)
  }
  if run.stderr != "" {
    @stdio.stderr.write(run.stderr)
  }
  exit_with_code(run.code)
}
