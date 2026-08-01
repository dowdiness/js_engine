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
extern "c" fn stderr_write_bytes(message : Bytes) -> Unit = "moonbit_execution_observation_inventory_stderr_write"

///|
fn exit_with_error() -> Unit {
  @sys.exit(1)
}

///|
fn eprintln(line : String) -> Unit {
  stderr_write_bytes(@utf8.encode(line + "\n"))
}

///|
fn main {
  let cmd = @argparse.Command(
    "execution-observation-inventory",
    options=[
      @argparse.OptionArg(
        "root",
        default_values=["."],
        about="Repository root containing scripts/execution_observation_inventory.json",
      ),
    ],
    about="Validate the Stage 4 execution observation inventory manifest.",
  )
  let matches = cmd.parse(argv=program_args(@env.args()), env=Map([])) catch {
    err => {
      eprintln("Error: \{err}")
      exit_with_error()
      return
    }
  }
  let root = match matches.values.get("root") {
    Some(values) if values.length() > 0 => values[0]
    _ => "."
  }
  let (stdout_lines, stderr_lines, code) = @inventory.run(root~)
  for line in stdout_lines {
    println(line)
  }
  for line in stderr_lines {
    eprintln(line)
  }
  if code != 0 {
    exit_with_error()
  }
}
