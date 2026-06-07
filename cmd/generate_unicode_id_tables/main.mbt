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
    "generate-unicode-id-tables-mbt",
    options=[
      @argparse.OptionArg(
        "unicode-version",
        default_values=["17.0.0"],
        about="Unicode version to fetch (default: 17.0.0)",
      ),
      @argparse.OptionArg(
        "output",
        about="output MoonBit source path (default: repo-root/lexer/unicode_id.mbt)",
      ),
    ],
    about="Generate lexer/unicode_id.mbt from Unicode DerivedCoreProperties.txt. MoonBit shadow; Python remains authoritative.",
  )
  let raw_args = @env.args()
  let matches = cmd.parse(argv=program_args(raw_args), env={}) catch {
    err => {
      @stdio.stderr.write(@helpers.cli_error_message(err) + "\n")
      @sys.exit(1)
      return
    }
  }
  let output = match optional_value(matches.values, "output") {
    Some(path) => path
    None => @helpers.repo_default_path(argv0(raw_args), "lexer/unicode_id.mbt")
  }
  let config = @helpers.UnicodeConfig(
    unicode_version=first_value(matches.values, "unicode-version", "17.0.0"),
    output~,
  )
  let run = @helpers.run_unicode_tables(config) catch {
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
