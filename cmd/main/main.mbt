///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    println("Usage: js_engine <javascript-code>")
    println("Example: js_engine 'console.log(1 + 2)'")
    return
  }
  let source = args[1]
  try {
    let (output, result) = @lib.run(source)
    for line in output {
      println(line)
    }
    if result != "undefined" {
      println(result)
    }
  } catch {
    Failure::Failure(msg) => println("Error: \{msg}")
    e => println("Error: \{e}")
  }
}
