///|
fn main {
  let args = @env.args()
  let (is_module, source) = parse_args(args)
  match source {
    None => {
      println("Usage: js_engine [--module] <javascript-code>")
      println("Example: js_engine 'console.log(1 + 2)'")
    }
    Some(src) =>
      try {
        if is_module {
          let (output, _) = @lib.run_module(src)
          for line in output {
            println(line)
          }
        } else {
          let (output, result) = @lib.run(src)
          for line in output {
            println(line)
          }
          if result != "undefined" {
            println(result)
          }
        }
      } catch {
        Failure::Failure(msg) => println("Error: \{msg}")
        e => println("Error: \{e}")
      }
  }
}
