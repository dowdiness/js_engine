///|
/// Test262 batch runner - processes tests from batch file
/// Input: batch-input.txt with test sources separated by <<<TESTSEP>>>
/// Output: Results printed to stdout (one per line: PASS/FAIL/ERROR)
fn main {
  let args = @env.args()

  if args.length() < 2 {
    println("Usage: moon run cmd/test262 <batch-file>")
    return
  }

  let batch_file = args[1]

  // Read entire batch file
  let content = match @fs.read_file_to_string(batch_file) {
    Ok(s) => s
    Err(e) => {
      println("ERROR: Failed to read batch file: \{e}")
      return
    }
  }

  // Split by test separator
  let tests = content.split("<<<TESTSEP>>>")

  println("READY:\{tests.length()}")  // Signal ready with test count

  // Process each test
  for test_source in tests {
    let trimmed = test_source.trim()
    if trimmed == "" {
      continue
    }

    // Execute test
    try {
      let (output, result) = @lib.run(trimmed)
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
}
