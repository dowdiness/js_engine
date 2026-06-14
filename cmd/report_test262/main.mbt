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
fn argv0(args : Array[String]) -> String {
  match args {
    [program, ..] => program
    [] => ""
  }
}

///|
fn is_report_format(value : String) -> Bool {
  value == "table" || value == "changelog"
}

///|
fn invalid_format_message(value : String) -> String {
  "error: argument --format: invalid choice: '" +
  value +
  "' (choose from 'table', 'changelog')"
}

///|
fn optional_int64_arg(raw : String?, label : String) -> Int64? raise {
  match raw {
    None => None
    Some(value) =>
      Some(
        @string.parse_int64(value) catch {
          _ => fail("error: " + label + " must be an integer")
        },
      )
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
    "report-test262-mbt",
    flags=[
      @argparse.FlagArg(
        "with-editions",
        about="also run cmd/classify_by_edition and print per-edition tables below the headline (table format only)",
      ),
      @argparse.FlagArg(
        "no-baseline",
        about="skip the CI regression baseline delta line",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "run",
        about="CI run id (default: latest successful main run)",
      ),
      @argparse.OptionArg(
        "repo",
        about="owner/name; default inferred from current repo by gh",
      ),
      @argparse.OptionArg(
        "workflow",
        default_values=["test262.yml"],
        about="workflow file name (default: test262.yml)",
      ),
      @argparse.OptionArg(
        "keep-artifacts",
        about="retain downloaded artifacts in DIR",
      ),
      @argparse.OptionArg(
        "format",
        default_values=["table"],
        about="table (markdown headline + per-mode table) or changelog (prose bullets). Default: table.",
      ),
      @argparse.OptionArg(
        "baseline",
        default_values=["test262-baseline.json"],
        about="baseline JSON path (default: test262-baseline.json; silently skipped if absent)",
      ),
    ],
    about="Download a test262 CI run's artifacts and print a paste-ready per-mode pass-rate block. MoonBit shadow; Python remains authoritative.",
  )
  let raw_args = @env.args()
  let matches = cmd.parse(argv=program_args(raw_args), env={}) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let run_id = optional_int64_arg(
    optional_value(matches.values, "run"),
    "--run",
  ) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let format = first_value(matches.values, "format", "table")
  if !is_report_format(format) {
    @stdio.stderr.write(invalid_format_message(format) + "\n")
    @sys.exit(2)
    return
  }
  let config = @helpers.ReportConfig(
    run_id~,
    repo=optional_value(matches.values, "repo"),
    workflow=first_value(matches.values, "workflow", "test262.yml"),
    keep_artifacts=optional_value(matches.values, "keep-artifacts"),
    with_editions=flag_value(matches.flags, "with-editions"),
    format~,
    baseline=first_value(matches.values, "baseline", "test262-baseline.json"),
    no_baseline=flag_value(matches.flags, "no-baseline"),
    repo_root=Some(@helpers.resolve_repo_root(argv0(raw_args))),
  )
  let run = @helpers.run_report(config) catch {
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
