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
    if args[i] == "--fixture" && i + 2 < args.length() {
      fixtures.push((args[i + 1], args[i + 2]))
      i = i + 3
    } else {
      rest.push(args[i])
      i = i + 1
    }
  }
  (fixtures, rest)
}

///|
fn main {
  let (fixtures, remaining) = extract_fixtures(program_args(@env.args()))
  let cmd = @argparse.Command(
    "js_engine",
    flags=[
      @argparse.FlagArg("module", about="Run input as an ES module"),
      @argparse.FlagArg(
        "annex-b",
        about="Enable Annex B (web compat) semantics",
      ),
    ],
    positionals=[
      @argparse.PositionArg("source", about="JavaScript source to execute"),
    ],
    about="JavaScript interpreter (use --fixture <spec> <src> to register a module fixture before main runs; may be repeated)",
    version="0.2.2",
  )
  let matches = cmd.parse(argv=remaining[:], env={}) catch {
    err => {
      println("\{err}")
      exit_with_error()
      return
    }
  }
  let is_module = match matches.flags.get("module") {
    Some(true) => true
    _ => false
  }
  let annex_b = match matches.flags.get("annex-b") {
    Some(true) => true
    _ => false
  }
  let source : String? = match matches.values.get("source") {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
  match source {
    None => {
      println(
        "Usage: js_engine [--module] [--annex-b] [--fixture <spec> <src>]... <javascript-code>",
      )
      println("Example: js_engine 'console.log(1 + 2)'")
    }
    Some(src) =>
      try {
        if is_module {
          // Run any fixture modules first (in dep order), then the main module.
          // run_modules registers each module's exports under its specifier so
          // the main test's `import` lookups succeed.
          let modules : Array[(String, String)] = []
          for f in fixtures {
            modules.push(f)
          }
          modules.push(("<test>", src))
          let (output, _) = @lib.run_modules(modules, annex_b~)
          for line in output {
            println(line)
          }
        } else {
          let (output, result) = @lib.run(src, annex_b~)
          for line in output {
            println(line)
          }
          if result != "undefined" {
            println(result)
          }
        }
      } catch {
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
