///|
fn run_js(source : String) -> (Array[String], @interpreter.Value) raise Error {
  let interp = @interpreter.Interpreter::new()
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  (interp.output, result)
}

///|
fn run_output(source : String) -> Array[String] raise Error {
  let (output, _) = run_js(source)
  output
}

///|
test "arithmetic" {
  let (_, result) = run_js("1 + 2 * 3")
  inspect(result, content="7")
}

///|
test "variables" {
  let (_, result) = run_js("let x = 10; let y = 20; x + y")
  inspect(result, content="30")
}

///|
test "string concatenation" {
  let (_, result) = run_js("\"hello\" + \" \" + \"world\"")
  inspect(result, content="hello world")
}

///|
test "console.log" {
  let output = run_output("console.log(\"hello\"); console.log(1 + 2)")
  inspect(output, content="[\"hello\", \"3\"]")
}

///|
test "if/else true" {
  let (_, result) = run_js("let x = 10; if (x > 5) { 1 } else { 2 }")
  inspect(result, content="1")
}

///|
test "if/else false" {
  let (_, result) = run_js("let x = 3; if (x > 5) { 1 } else { 2 }")
  inspect(result, content="2")
}

///|
test "while loop" {
  let output = run_output(
    "let i = 0; while (i < 3) { console.log(i); i = i + 1 }",
  )
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "for loop" {
  let output = run_output(
    "for (let i = 0; i < 3; i = i + 1) { console.log(i) }",
  )
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "function declaration and call" {
  let (_, result) = run_js("function add(a, b) { return a + b; } add(3, 4)")
  inspect(result, content="7")
}

///|
test "closure" {
  let src =
    #|function makeCounter() {
    #|  let count = 0;
    #|  return function() { count = count + 1; return count; };
    #|}
    #|let counter = makeCounter();
    #|console.log(counter());
    #|console.log(counter());
    #|console.log(counter());
  let output = run_output(src)
  inspect(output, content="[\"1\", \"2\", \"3\"]")
}

///|
test "recursive fibonacci" {
  let src =
    #|function fib(n) {
    #|  if (n <= 1) { return n; }
    #|  return fib(n - 1) + fib(n - 2);
    #|}
    #|console.log(fib(10));
  let output = run_output(src)
  inspect(output, content="[\"55\"]")
}

///|
test "ternary expression" {
  let (_, result) = run_js("let x = 5; x > 3 ? \"big\" : \"small\"")
  inspect(result, content="big")
}

///|
test "typeof" {
  let output = run_output(
    "console.log(typeof 42); console.log(typeof \"hi\"); console.log(typeof true); console.log(typeof null); console.log(typeof undefined)",
  )
  inspect(
    output,
    content="[\"number\", \"string\", \"boolean\", \"object\", \"undefined\"]",
  )
}

///|
test "break in while" {
  let src =
    #|let i = 0;
    #|while (true) {
    #|  if (i >= 3) { break; }
    #|  console.log(i);
    #|  i = i + 1;
    #|}
  let output = run_output(src)
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "continue in for" {
  let src =
    #|for (let i = 0; i < 5; i = i + 1) {
    #|  if (i === 2 || i === 4) { continue; }
    #|  console.log(i);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"0\", \"1\", \"3\"]")
}

///|
test "const assignment error" {
  let mut err_msg = ""
  try {
    let _ = run_js("const x = 5; x = 10")

  } catch {
    Failure::Failure(msg) => err_msg = msg
    _ => err_msg = "unexpected error"
  }
  inspect(err_msg, content="Assignment to constant variable 'x'")
}

///|
test "strict equality" {
  let output = run_output(
    "console.log(1 === 1); console.log(1 === 2); console.log(null === undefined)",
  )
  inspect(output, content="[\"true\", \"false\", \"false\"]")
}

///|
test "loose equality null/undefined" {
  let output = run_output(
    "console.log(null == undefined); console.log(undefined == null)",
  )
  inspect(output, content="[\"true\", \"true\"]")
}

///|
test "logical operators short-circuit" {
  let output = run_output(
    "console.log(false && 42); console.log(true || 42); console.log(0 || \"default\")",
  )
  inspect(output, content="[\"false\", \"true\", \"default\"]")
}

///|
test "unary not" {
  let (_, result) = run_js("!false")
  inspect(result, content="true")
}

///|
test "unary minus" {
  let (_, result) = run_js("-5 + 3")
  inspect(result, content="-2")
}

///|
test "nested function scope" {
  let src =
    #|let x = "global";
    #|function outer() {
    #|  let x = "outer";
    #|  function inner() {
    #|    return x;
    #|  }
    #|  return inner();
    #|}
    #|console.log(outer());
  let output = run_output(src)
  inspect(output, content="[\"outer\"]")
}

///|
test "string and number concatenation" {
  let (_, result) = run_js("\"value: \" + 42")
  inspect(result, content="value: 42")
}

///|
test "modulo operator" {
  let (_, result) = run_js("10 % 3")
  inspect(result, content="1")
}

///|
test "comparison operators" {
  let output = run_output(
    "console.log(1 < 2); console.log(2 > 1); console.log(1 <= 1); console.log(1 >= 2)",
  )
  inspect(output, content="[\"true\", \"true\", \"true\", \"false\"]")
}

///|
test "fizzbuzz" {
  let src =
    #|for (let i = 1; i <= 15; i = i + 1) {
    #|  if (i % 15 === 0) { console.log("FizzBuzz"); }
    #|  else if (i % 3 === 0) { console.log("Fizz"); }
    #|  else if (i % 5 === 0) { console.log("Buzz"); }
    #|  else { console.log(i); }
    #|}
  let output = run_output(src)
  inspect(
    output,
    content="[\"1\", \"2\", \"Fizz\", \"4\", \"Buzz\", \"Fizz\", \"7\", \"8\", \"Fizz\", \"Buzz\", \"11\", \"Fizz\", \"13\", \"14\", \"FizzBuzz\"]",
  )
}
