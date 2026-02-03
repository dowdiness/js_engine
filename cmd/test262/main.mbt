///|
/// Test262 batch runner - processes tests from batch file
/// Input: batch-input.txt with test sources separated by <<<TESTSEP>>>
/// Output: Results printed to stdout (one per line: PASS/FAIL/ERROR)

fn read_batch_file(path : String) -> String!  {
  @fs.read_file_to_string!(path)
}

fn main {
  let args = @env.args()

  if args.length() < 2 {
    println("Usage: moon run cmd/test262 <batch-file>")
    return
  }

  let batch_file = args[1]

  // Read entire batch file
  let content = try {
    read_batch_file!(batch_file)
  } catch {
    e => {
      println("ERROR: Failed to read batch file: \{e}")
      return
    }
  }

  // Split by test separator and filter empty strings
  let separator = "<<<TESTSEP>>>"
  let tests_raw = content.split(separator)
  let mut tests : Array[String] = []

  for test_str in tests_raw {
    if test_str.length() > 0 {
      tests.push(test_str)
    }
  }

  println("READY:\{tests.length()}")  // Signal ready with test count

  // Process each test
  for test_source in tests {
    // Skip empty tests
    if test_source.length() == 0 {
      continue
    }

    // Execute test
    try {
      let (output, _result) = @lib.run(test_source)
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
