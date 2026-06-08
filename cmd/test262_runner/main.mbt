///|
fn program_args(args : Array[String]) -> ArrayView[String] {
  match args {
    [_, .. rest] => rest
    [] => args[0:]
  }
}

///|
fn first_value(
  values : Map[String, Array[String]],
  key : String,
  default : String,
) -> String {
  match values.get(key) {
    Some([first, ..]) => first
    _ => default
  }
}

///|
fn optional_value(values : Map[String, Array[String]], key : String) -> String? {
  match values.get(key) {
    Some([first, ..]) => Some(first)
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
    _ => fail("argument \{label}: invalid int value: '\{raw}'")
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
async fn exit_cli_error(message : String) -> Unit {
  @stdio.stderr.write("test262-runner.py: error: " + message + "\n")
  @sys.exit(2)
}

///|
fn first_single_quoted_value(message : String) -> String? {
  match message.split_once("'") {
    Some((_, rest)) =>
      match rest.to_owned().split_once("'") {
        Some((value, _)) => Some(value.to_owned())
        None => None
      }
    None => None
  }
}

///|
fn normalize_parse_error(message : String) -> String {
  let head = match message.split_once("\n\nUsage:") {
    Some((before_usage, _)) => before_usage.to_owned()
    None => message
  }
  if head.has_prefix("error: unexpected argument ") {
    match first_single_quoted_value(head) {
      Some(arg) => "unrecognized arguments: " + arg
      None => head["error: ".length():].to_owned()
    }
  } else if head.has_prefix("error: a value is required for ") {
    match first_single_quoted_value(head) {
      Some(arg) => "argument " + arg + ": expected one argument"
      None => head["error: ".length():].to_owned()
    }
  } else if head.has_prefix("error: ") {
    head["error: ".length():].to_owned()
  } else {
    head
  }
}

///|
async fn exit_runtime_error(message : String) -> Unit {
  let rendered = match message.view() {
    [.. "Error: ", ..] => message
    _ => "Error: " + message
  }
  @stdio.stderr.write(rendered + "\n")
  @sys.exit(1)
}

///|
async fn main {
  let cmd = @argparse.Command(
    "test262-runner.py",
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
        allow_hyphen_values=true,
        about="Start at expanded task offset N (0-based)",
      ),
      @argparse.OptionArg(
        "count",
        allow_hyphen_values=true,
        about="Run at most N expanded tasks",
      ),
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
        allow_hyphen_values=true,
        about="Timeout per test in seconds (default: 5)",
      ),
      @argparse.OptionArg(
        "threads",
        allow_hyphen_values=true,
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
      exit_cli_error(normalize_parse_error(@helpers.cli_error_message(err)))
      return
    }
  }
  let start = parse_int_arg(
    first_value(matches.values, "start", "0"),
    "--start",
  ) catch {
    err => {
      exit_cli_error(@helpers.cli_error_message(err))
      return
    }
  }
  let count = optional_int_arg(
    optional_value(matches.values, "count"),
    "--count",
  ) catch {
    err => {
      exit_cli_error(@helpers.cli_error_message(err))
      return
    }
  }
  let timeout = parse_int_arg(
    first_value(matches.values, "timeout", "5"),
    "--timeout",
  ) catch {
    err => {
      exit_cli_error(@helpers.cli_error_message(err))
      return
    }
  }
  let threads = optional_int_arg(
    optional_value(matches.values, "threads"),
    "--threads",
  ) catch {
    err => {
      exit_cli_error(@helpers.cli_error_message(err))
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
          exit_cli_error(@helpers.cli_error_message(err))
          return
        }
      },
    )
  }
  let harness_options = @runner.HarnessOptions::from_cli(
    all_values(matches.values, "harness-helper"),
  ) catch {
    err => {
      exit_cli_error(@helpers.cli_error_message(err))
      return
    }
  }
  guard start >= 0 else {
    exit_cli_error("--start must be >= 0")
    return
  }
  match count {
    Some(value) if value < 0 => {
      exit_cli_error("--count must be >= 0")
      return
    }
    _ => ()
  }
  guard !(shard is Some(_) && (start != 0 || count is Some(_))) else {
    exit_cli_error("--shard cannot be combined with --start/--count")
    return
  }
  let mode = first_value(matches.values, "mode", "both")
  guard mode == "both" || mode == "strict" || mode == "non-strict" else {
    exit_cli_error(
      "argument --mode: invalid choice: '\{mode}' (choose from 'both', 'strict', 'non-strict')",
    )
    return
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
    mode~,
    harness_options~,
    repo_root=@helpers.resolve_repo_root(argv0(raw_args)),
  )
  let run = @runner.run_runner(config) catch {
    err => {
      exit_runtime_error(@helpers.cli_error_message(err))
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
