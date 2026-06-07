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
fn all_values(
  values : Map[String, Array[String]],
  key : String,
) -> Array[String] {
  match values.get(key) {
    Some(items) => items
    None => []
  }
}

///|
fn flag_value(flags : Map[String, Bool], key : String) -> Bool {
  match flags.get(key) {
    Some(value) => value
    None => false
  }
}

///|
fn parse_int_arg(raw : String, label : String) -> Int raise {
  @string.parse_int(raw) catch {
    _ => fail("error: \{label} must be an integer")
  }
}

///|
fn optional_int_arg(raw : String?, label : String) -> Int? raise {
  match raw {
    None => None
    Some(value) => Some(parse_int_arg(value, label))
  }
}

///|
fn argv0(args : Array[String]) -> String {
  match args {
    [program, ..] => program
    [] => ""
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
    "test262-runner-mbt",
    flags=[
      @argparse.FlagArg(
        "summary",
        about="Print summary only (no individual failures)",
      ),
      @argparse.FlagArg("verbose", about="Print each test result as it runs"),
    ],
    options=[
      @argparse.OptionArg(
        "engine",
        about="Command to invoke the JS engine (default: auto-detect built JS bundle)",
      ),
      @argparse.OptionArg(
        "test262",
        default_values=["./test262"],
        about="Path to test262 directory",
      ),
      @argparse.OptionArg(
        "filter",
        default_values=[""],
        about="Only run tests matching this pattern (e.g. 'language/expressions')",
      ),
      @argparse.OptionArg(
        "tests-file",
        default_values=[""],
        about="Run an explicit newline-delimited list of test files",
      ),
      @argparse.OptionArg(
        "start",
        default_values=["0"],
        about="Start at expanded task offset N (0-based)",
      ),
      @argparse.OptionArg("count", about="Run at most N expanded tasks"),
      @argparse.OptionArg(
        "shard",
        default_values=[""],
        about="Run balanced contiguous shard I/N after mode expansion",
      ),
      @argparse.OptionArg(
        "resume-from",
        default_values=[""],
        about="Skip expanded tasks already present in a results JSON file",
      ),
      @argparse.OptionArg(
        "log",
        default_values=[""],
        about="Write a per-task JSONL progress log",
      ),
      @argparse.OptionArg(
        "merged-log",
        default_values=[""],
        about="Append fail/timeout/error JSONL records for shard merging",
      ),
      @argparse.OptionArg(
        "timeout",
        default_values=["5"],
        about="Timeout per test in seconds (default: 5)",
      ),
      @argparse.OptionArg(
        "threads",
        about="Number of parallel workers (default: auto-detect CPU count, minimum 4)",
      ),
      @argparse.OptionArg(
        "output",
        default_values=[""],
        about="Write JSON results to this file",
      ),
      @argparse.OptionArg(
        "mode",
        default_values=["both"],
        about="Test mode: 'strict' only, 'non-strict' only, or 'both' (default: both)",
      ),
      @argparse.OptionArg(
        "harness-helper",
        action=Append,
        about="Opt into modified Test262 harness helper(s); currently: codePointRange",
      ),
    ],
    about="MoonBit async Test262 runner shadow. Python scripts/test262-runner.py remains authoritative.",
  )
  let raw_args = @env.args()
  let matches = cmd.parse(argv=program_args(raw_args), env={}) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let start = parse_int_arg(
    first_value(matches.values, "start", "0"),
    "--start",
  ) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let count = optional_int_arg(
    optional_value(matches.values, "count"),
    "--count",
  ) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let timeout = parse_int_arg(
    first_value(matches.values, "timeout", "5"),
    "--timeout",
  ) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let threads = optional_int_arg(
    optional_value(matches.values, "threads"),
    "--threads",
  ) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let shard_raw = first_value(matches.values, "shard", "")
  let shard = if shard_raw == "" {
    None
  } else {
    Some(
      @runner.parse_shard_spec(shard_raw) catch {
        err => {
          @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
          @sys.exit(1)
          return
        }
      },
    )
  }
  let harness_options = @runner.HarnessOptions::from_cli(
    all_values(matches.values, "harness-helper"),
  ) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let config = @runner.RunnerConfig(
    engine=optional_value(matches.values, "engine"),
    test262=first_value(matches.values, "test262", "./test262"),
    filter=first_value(matches.values, "filter", ""),
    tests_file=first_value(matches.values, "tests-file", ""),
    start~,
    count~,
    shard~,
    resume_from=first_value(matches.values, "resume-from", ""),
    log=first_value(matches.values, "log", ""),
    merged_log=first_value(matches.values, "merged-log", ""),
    timeout~,
    threads~,
    output=first_value(matches.values, "output", ""),
    summary=flag_value(matches.flags, "summary"),
    verbose=flag_value(matches.flags, "verbose"),
    mode=first_value(matches.values, "mode", "both"),
    harness_options~,
    repo_root=@helpers.resolve_repo_root(argv0(raw_args)),
  )
  let run = @runner.run_runner(config) catch {
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
