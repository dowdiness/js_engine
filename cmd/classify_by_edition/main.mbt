///|
fn program_args(args : Array[String]) -> ArrayView[String] {
  if args.length() >= 1 {
    args[1:]
  } else {
    args[0:]
  }
}

///|
#borrow(message)
extern "c" fn stderr_write_bytes(message : Bytes) -> Unit = "moonbit_classify_by_edition_stderr_write"

///|
fn eprintln(line : String) -> Unit {
  stderr_write_bytes(@utf8.encode(line + "\n"))
}

///|
fn exit_with_code(code : Int) -> Unit {
  if code != 0 {
    @sys.exit(code)
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
fn parse_top(raw : String) -> Int {
  @string.parse_int(raw) catch {
    _ => 15
  }
}

///|
fn main {
  let cmd = @argparse.Command(
    "classify-by-edition-mbt",
    flags=[
      @argparse.FlagArg(
        "markdown",
        about="Emit markdown tables (default; accepted for Python CLI parity)",
      ),
      @argparse.FlagArg("show-unmapped", about="Print unmapped features seen"),
      @argparse.FlagArg("list-failures", about="Per-edition failure breakdown"),
    ],
    options=[
      @argparse.OptionArg(
        "test262-root",
        default_values=["."],
        about="Directory containing test262/ subdir (default: .)",
      ),
      @argparse.OptionArg(
        "edition",
        about="With --list-failures, narrow to a single edition",
      ),
      @argparse.OptionArg(
        "top",
        default_values=["15"],
        about="Number of entries shown per failure breakdown section (default 15)",
      ),
      @argparse.OptionArg(
        "json-output",
        default_values=[""],
        about="Also write per-mode, per-edition counts as JSON to this path",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "results",
        num_args=@argparse.ValueRange(lower=1),
        about="test262-*-results.json path(s)",
      ),
    ],
    about="MoonBit shadow classifier for existing Test262 result artifacts by ECMAScript edition.",
  )
  let matches = cmd.parse(argv=program_args(@env.args()), env={}) catch {
    err => {
      eprintln("\{err}")
      @sys.exit(1)
      return
    }
  }
  let result_paths = match matches.values.get("results") {
    Some(values) => values
    None => []
  }
  let run = @tools.run_classify_by_edition(
    result_paths,
    test262_root=first_value(matches.values, "test262-root", "."),
    show_unmapped=flag_value(matches.flags, "show-unmapped"),
    list_failures=flag_value(matches.flags, "list-failures"),
    edition_filter=optional_value(matches.values, "edition"),
    top=parse_top(first_value(matches.values, "top", "15")),
    json_output=first_value(matches.values, "json-output", ""),
  ) catch {
    err => {
      eprintln("Error: \{err}")
      @sys.exit(1)
      return
    }
  }
  for line in run.stdout_lines {
    println(line)
  }
  for line in run.stderr_lines {
    eprintln(line)
  }
  exit_with_code(run.code)
}
