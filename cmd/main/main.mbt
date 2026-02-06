///|
fn main {
  let source = get_source_arg()
  match source {
    None => {
      println("Usage: js_engine <javascript-code>")
      println("Example: js_engine 'console.log(1 + 2)'")
    }
    Some(src) =>
      try {
        let (output, result) = @lib.run(src)
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
}
