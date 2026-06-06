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
extern "c" fn stderr_write_bytes(message : Bytes) -> Unit = "moonbit_architecture_state_audit_stderr_write"

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
    "architecture-state-audit",
    flags=[
      @argparse.FlagArg(
        "list",
        about="Print the classified mutable state inventory.",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "root",
        default_values=["."],
        about="Repository root to scan (default: current directory)",
      ),
    ],
    about="Check runtime/stdlib module-level mutable state against the Stage 0 architecture migration inventory.",
  )
  let matches = cmd.parse(argv=program_args(@env.args()), env={}) catch {
    err => {
      eprintln("\{err}")
      exit_with_error()
      return
    }
  }
  let root = match matches.values.get("root") {
    Some(values) if values.length() > 0 => values[0]
    _ => "."
  }
  let list = match matches.flags.get("list") {
    Some(true) => true
    _ => false
  }
  let (stdout_lines, stderr_lines, code) = @audit.run(root~, list~) catch {
    err => {
      eprintln("Error: \{err}")
      exit_with_error()
      return
    }
  }
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
