///|
/// Test262 batch runner - executes tests from stdin without process overhead
/// Protocol:
///   - Python sends: <<<SOURCE>>>\n<javascript>\n<<<END>>>
///   - MoonBit responds: PASS or FAIL or ERROR
fn main {
  println("READY")  // Signal ready

  loop {
    // Read until we see <<<SOURCE>>> or EXIT
    let start_line = @io.stdin().read_line()
    match start_line {
      Ok(line) => {
        let trimmed = line.trim()
        if trimmed == "EXIT" {
          break
        }
        if trimmed != "<<<SOURCE>>>" {
          continue  // Wait for correct start marker
        }

        // Read source until <<<END>>>
        let mut source_lines : Array[String] = []
        loop {
          let source_line = @io.stdin().read_line()
          match source_line {
            Ok(s) => {
              if s.trim() == "<<<END>>>" {
                break
              }
              source_lines.push(s)
            }
            Err(_) => break
          }
        }

        let source = source_lines.join("\n")

        // Execute test
        try {
          let (output, result) = @lib.run(source)
          let output_str = output.join("\n")

          if output_str.contains("Error:") || output_str.contains("Test262Error") {
            println("FAIL")
          } else {
            println("PASS")
          }
        } catch {
          _ => println("ERROR")
        }
      }
      Err(_) => break
    }
  }
}
