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
        @interpreter.JsException(value) => println("\{value}")
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
