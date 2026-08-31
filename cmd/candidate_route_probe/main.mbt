///|
const ROUTE_PROBE_USAGE : String = "Usage: candidate-route-probe <script.js>"

///|
#borrow(message)
extern "c" fn stderr_write_bytes(message : Bytes) -> Unit = "moonbit_candidate_route_probe_stderr_write"

///|
fn program_args(args : Array[String]) -> ArrayView[String] {
  if args.length() > 0 {
    args[1:]
  } else {
    args[0:]
  }
}

///|
fn route_probe_report(source : String) -> Json raise {
  let program = @parser.parse(source)
  @compiler.profile_candidate_route_plan_json(program.stmts)
}

///|
fn route_probe_error_message(message : String) -> String {
  "Error: " + message
}

///|
fn eprintln(line : String) -> Unit {
  stderr_write_bytes(@utf8.encode(line + "\n"))
}

///|
fn exit_with_error() -> Unit {
  @sys.exit(1)
}

///|
fn print_usage() -> Unit {
  println(ROUTE_PROBE_USAGE)
}

///|
fn print_usage_error() -> Unit {
  eprintln(ROUTE_PROBE_USAGE)
}

///|
fn main {
  let args = program_args(@env.args())
  if args.length() == 1 && (args[0] == "--help" || args[0] == "-h") {
    print_usage()
    return
  }
  guard args.length() == 1 else {
    print_usage_error()
    exit_with_error()
    return
  }
  let result : Result[Json, Error] = Ok(
    route_probe_report(@fs.read_file_to_string(args[0])),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(report) => println(report.stringify(indent=2))
    Err(error) => {
      eprintln(route_probe_error_message(error.to_string()))
      exit_with_error()
    }
  }
}
