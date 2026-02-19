///|
fn main {
  let args = @env.args()
  let (is_module, annex_b, source) = parse_args(args)
  match source {
    None => {
      println("Usage: js_engine [--module] [--annex-b] <javascript-code>")
      println("Example: js_engine 'console.log(1 + 2)'")
    }
    Some(src) =>
      try {
        if is_module {
          let (output, _) = @lib.run_module(src, annex_b~)
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
        @interpreter.JsException(value) =>
          match value {
            Object(data) if data.class_name.has_suffix("Error") => {
              let name : String = match data.properties.get("name") {
                Some(String_(s)) => s
                _ => data.class_name
              }
              let msg : String = match data.properties.get("message") {
                Some(String_(s)) => s
                _ => ""
              }
              println("\{name}: \{msg}")
            }
            Object(data) if data.properties.contains("message") => {
              // Error-like object (e.g. new Test262Error()): find constructor name from prototype
              let ctor_name : String? = match data.prototype {
                Object(proto_data) =>
                  match proto_data.properties.get("constructor") {
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
                  let msg : String = match data.properties.get("message") {
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
        @errors.TypeError(message~) => println("TypeError: \{message}")
        @errors.ReferenceError(message~) =>
          println("ReferenceError: \{message}")
        @errors.SyntaxError(message~) => println("SyntaxError: \{message}")
        @errors.RangeError(message~) => println("RangeError: \{message}")
        @errors.URIError(message~) => println("URIError: \{message}")
        @errors.EvalError(message~) => println("EvalError: \{message}")
        @errors.InternalError(message~) => println("InternalError: \{message}")
        Failure::Failure(msg) => println("Error: \{msg}")
        e => println("Error: \{e}")
      }
  }
}
