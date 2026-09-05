///|
/// Pre-extract every `--fixture <spec> <src>` triple from `args`, returning the
/// extracted pairs and the remaining argv (to hand to argparse).
///
/// `--fixture` takes two adjacent values per occurrence, which doesn't fit
/// argparse's one-value-per-OptionArg model. Pulling the triples out here
/// preserves the original adjacency contract (each `<src>` always belongs to
/// the immediately-preceding `<spec>`), regardless of where in argv they sit.
fn extract_fixtures(
  args : ArrayView[String],
) -> (Array[(String, String)], Array[String]) {
  let fixtures : Array[(String, String)] = []
  let rest : Array[String] = []
  let mut i = 0
  while i < args.length() {
    if args[i] == "--" {
      for j = i; j < args.length(); j = j + 1 {
        rest.push(args[j])
      }
      return (fixtures, rest)
    } else if args[i] == "--fixture" {
      // `--fixture` always consumes the next two argv slots. Erroring here
      // (rather than letting it fall through to argparse) is required because
      // argparse also declares `--fixture` for help rendering, so a malformed
      // single-value form would otherwise be silently mis-parsed.
      guard i + 2 < args.length() else {
        println("error: --fixture requires two values: --fixture <spec> <src>")
        exit_with_error()
        return (fixtures, rest)
      }
      fixtures.push((args[i + 1], args[i + 2]))
      i = i + 3
    } else if args[i].has_prefix("--fixture=") {
      // argparse accepts the inline `--fixture=spec` form because we declare
      // `fixture` as an OptionArg for --help discovery. Reject it loudly here
      // — the two-value contract requires separate-token form.
      println("error: --fixture requires two values: --fixture <spec> <src>")
      exit_with_error()
      return (fixtures, rest)
    } else {
      rest.push(args[i])
      i = i + 1
    }
  }
  (fixtures, rest)
}

///|
/// argparse cannot distinguish eval-mode arguments after `--` from the file
/// positional. Remove that delimiter only when an eval option precedes it.
fn split_eval_arguments(args : Array[String]) -> (Array[String], Array[String]) {
  let mut separator = -1
  let mut has_eval = false
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == "-e" || args[i] == "--eval" || args[i].has_prefix("--eval=") {
      has_eval = true
    }
    if args[i] == "--" {
      separator = i
      break
    }
  }
  if !has_eval || separator < 0 {
    return (args, [])
  }
  let command_args : Array[String] = []
  let script_args : Array[String] = []
  for i = 0; i < separator; i = i + 1 {
    command_args.push(args[i])
  }
  for i = separator + 1; i < args.length(); i = i + 1 {
    script_args.push(args[i])
  }
  (command_args, script_args)
}

///|
fn resolve_shell_identity(request : String, referrer : String?) -> String {
  let base = match referrer {
    Some(path) => @path.Path::dirname(path).to_string()
    None => @env.current_dir().unwrap_or(".")
  }
  if @path.Path::is_absolute(request) {
    @path.Path::normalize(request).to_string()
  } else {
    @path.Path::normalize(@path.Path::join(base, request).to_string()).to_string()
  }
}

///|
fn resolve_shell_script(
  request : String,
  referrer : String?,
) -> @lib.LoadedScript raise {
  let identity = resolve_shell_identity(request, referrer)
  let source = @fs.read_file_to_string(identity)
  @lib.LoadedScript(identity~, source~)
}

///|
fn resolve_shell_bytes(request : String, referrer : String?) -> Bytes raise {
  let identity = resolve_shell_identity(request, referrer)
  @fs.read_file_to_bytes(identity)
}

///|
fn main {
  let (fixtures, remaining) = extract_fixtures(program_args(@env.args()))
  let (command_args, eval_arguments) = split_eval_arguments(remaining)
  let cmd = @argparse.Command(
    "js_engine",
    flags=[
      @argparse.FlagArg("module", about="Run input as an ES module"),
      @argparse.FlagArg(
        "annex-b",
        about="Enable Annex B (web compat) semantics",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "eval",
        short='e',
        about="Evaluate JavaScript source instead of reading a script file",
      ),
      // Documented for --help only; the actual `--fixture <spec> <src>` triples
      // are pre-extracted from argv by extract_fixtures() before argparse runs,
      // because argparse OptionArgs accept a single value per occurrence.
      @argparse.OptionArg(
        "fixture",
        action=Append,
        about="<spec> <src> — register a module fixture (may be repeated)",
      ),
      @argparse.OptionArg(
        "module-specifier",
        about="specifier to register the main module under",
      ),
    ],
    positionals=[
      @argparse.PositionArg("script", about="JavaScript file to execute"),
      @argparse.PositionArg(
        "script_args",
        num_args=@argparse.ValueRange(lower=0),
        allow_hyphen_values=true,
        about="Arguments exposed to the script as globalThis.arguments",
      ),
    ],
    about="JavaScript interpreter",
    version="0.8.1",
  )
  let matches = cmd.parse(argv=command_args[:], env=Map([])) catch {
    err => {
      println("\{err}")
      exit_with_error()
      return
    }
  }
  let is_module = matches.flags.get_or_default("module", false)
  let annex_b = matches.flags.get_or_default("annex-b", false)
  let eval_source : String? = match matches.values.get("eval") {
    Some(values) if values.length() > 0 => Some(values[0])
    _ => None
  }
  let script : String? = match matches.values.get("script") {
    Some(values) if values.length() > 0 => Some(values[0])
    _ => None
  }
  let positional_script_args = match matches.values.get("script_args") {
    Some(values) => values
    None => []
  }
  let script_args = if eval_arguments.length() > 0 {
    eval_arguments
  } else {
    positional_script_args
  }
  if eval_source is Some(_) && script is Some(_) {
    println("error: --eval cannot be combined with a script file")
    exit_with_error()
    return
  }
  let main_module_specifier = match matches.values.get("module-specifier") {
    Some(arr) if arr.length() > 0 => arr[0]
    _ => "<test>"
  }
  match (eval_source, script) {
    (None, None) => {
      println(
        "Usage: js_engine [--module] [--annex-b] [--fixture <spec> <src>]... <script.js>",
      )
      println("       js_engine -e <javascript-code>")
    }
    _ =>
      try {
        let clock_origin = @bench.monotonic_clock_start()
        let shell = @lib.Shell(
          load_source=resolve_shell_script,
          read_bytes=Some(resolve_shell_bytes),
          now_millis=Some(() => {
            @bench.monotonic_clock_end(clock_origin) / 1000.0
          }),
          annex_b~,
        )
        let script_name = match script {
          Some(path) => path
          None => "-e"
        }
        if script is Some(_) || script_args.length() > 0 {
          shell.set_arguments(script_name, script_args)
        }
        let execution : Result[Unit, Error] = Ok(
          {
            if is_module {
              let src = match (eval_source, script) {
                (Some(source), _) => source
                (_, Some(path)) => @fs.read_file_to_string(path)
                _ => ""
              }
              let registered_specifiers : @set.Set[String] = Default::default()
              for fixture in fixtures {
                let (specifier, _) = fixture
                if registered_specifiers.contains(specifier) {
                  println("error: duplicate module specifier '\{specifier}'")
                  exit_with_error()
                  return
                }
                registered_specifiers.add(specifier)
              }
              if registered_specifiers.contains(main_module_specifier) {
                println(
                  "error: duplicate module specifier '\{main_module_specifier}'",
                )
                exit_with_error()
                return
              }
              // Run fixture modules plus the main module through the graph
              // runner in the same Realm that owns the Shell host globals.
              let modules : Array[(String, String)] = []
              for f in fixtures {
                modules.push(f)
              }
              modules.push((main_module_specifier, src))
              shell.run_modules(modules)
            } else {
              match (eval_source, script) {
                (Some(source), _) => shell.eval(source)
                (_, Some(path)) => shell.run_file(path)
                _ => ()
              }
            }
            shell.drain_jobs()
          },
        ) catch {
          err => Err(err)
        }
        for line in shell.take_output() {
          println(line)
        }
        match execution {
          Ok(_) => ()
          Err(err) => raise err
        }
      } catch {
        @lib.JavaScriptException(message) => {
          println(message)
          exit_with_error()
        }
        @runtime.JsException(value) => {
          match value {
            Object(data) if data.class_name.has_suffix("Error") => {
              let name : String = match data.bag.properties.get("name") {
                Some(String_(s)) => s
                _ => data.class_name
              }
              let msg : String = match data.bag.properties.get("message") {
                Some(String_(s)) => s
                _ => ""
              }
              println("\{name}: \{msg}")
            }
            Object(data) if data.bag.properties.contains("message") => {
              // Error-like object (e.g. new Test262Error()): find constructor name from prototype
              let ctor_name : String? = match data.prototype {
                Object(proto_data) =>
                  match proto_data.bag.properties.get("constructor") {
                    Some(Object(ctor_data)) =>
                      match ctor_data.callable {
                        Some(UserFunc(fd)) => fd.name
                        Some(UserFuncExt(fd)) => fd.name
                        _ => None
                      }
                    _ => None
                  }
                _ => None
              }
              // Only format as "Name: message" if the constructor name ends with "Error"
              match ctor_name {
                Some(name) if name.has_suffix("Error") => {
                  let msg : String = match data.bag.properties.get("message") {
                    Some(String_(s)) => s
                    _ => ""
                  }
                  println("\{name}: \{msg}")
                }
                _ => println("\{value}")
              }
            }
            _ => println("\{value}")
          }
          exit_with_error()
        }
        Failure::Failure(msg) => {
          println("Error: \{msg}")
          exit_with_error()
        }
        e => {
          match @errors.format_if_js_error(e) {
            Some(msg) => println(msg)
            None => println("Error: \{e}")
          }
          exit_with_error()
        }
      }
  }
}
