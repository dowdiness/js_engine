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
extern "c" fn stderr_write_bytes(message : Bytes) -> Unit = "moonbit_test262_validate_skips_stderr_write"

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
fn main {
  let cmd = @argparse.Command(
    "test262-validate-skips-mbt",
    options=[
      @argparse.OptionArg(
        "test262",
        default_values=["./test262"],
        about="Path to the Test262 checkout (default: ./test262)",
      ),
      @argparse.OptionArg(
        "repo-root",
        default_values=["."],
        about="Repository root containing scripts/test262_skip_metadata.json (default: .)",
      ),
    ],
    about="MoonBit shadow validator for shared Test262 skip metadata; does not run tests or produce conformance numbers.",
  )
  let matches = cmd.parse(argv=program_args(@env.args()), env={}) catch {
    err => {
      eprintln("\{err}")
      @sys.exit(1)
      return
    }
  }
  let run = @tools.run_validate_skips(
    repo_root=first_value(matches.values, "repo-root", "."),
    test262_root=first_value(matches.values, "test262", "./test262"),
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
