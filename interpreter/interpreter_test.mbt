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
test "string comparison" {
  let output = run_output(
    "console.log(\"a\" < \"b\"); console.log(\"z\" > \"a\"); console.log(\"abc\" <= \"abd\"); console.log(\"x\" >= \"y\")",
  )
  inspect(output, content="[\"true\", \"true\", \"true\", \"false\"]")
}

///|
test "typeof function" {
  let output = run_output(
    "console.log(typeof function() {}); function foo() {} console.log(typeof foo)",
  )
  inspect(output, content="[\"function\", \"function\"]")
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

///|
test "throw/catch basic" {
  let src =
    #|try {
    #|  throw "oops";
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"oops\"]")
}

///|
test "throw/catch with number" {
  let src =
    #|try {
    #|  throw 42;
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
}

///|
test "throw stops execution" {
  let src =
    #|try {
    #|  console.log("before");
    #|  throw "error";
    #|  console.log("after");
    #|} catch (e) {
    #|  console.log("caught: " + e);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"before\", \"caught: error\"]")
}

///|
test "try/catch/finally" {
  let src =
    #|try {
    #|  throw "err";
    #|} catch (e) {
    #|  console.log("caught");
    #|} finally {
    #|  console.log("finally");
    #|}
  let output = run_output(src)
  inspect(output, content="[\"caught\", \"finally\"]")
}

///|
test "finally runs without exception" {
  let src =
    #|try {
    #|  console.log("try");
    #|} catch (e) {
    #|  console.log("catch");
    #|} finally {
    #|  console.log("finally");
    #|}
  let output = run_output(src)
  inspect(output, content="[\"try\", \"finally\"]")
}

///|
test "try/finally without catch" {
  let src =
    #|let x = "before";
    #|try {
    #|  x = "inside";
    #|} finally {
    #|  console.log("finally: " + x);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"finally: inside\"]")
}

///|
test "throw propagates through functions" {
  let src =
    #|function boom() { throw "bang"; }
    #|try {
    #|  boom();
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"bang\"]")
}

///|
test "nested try/catch" {
  let src =
    #|try {
    #|  try {
    #|    throw "inner";
    #|  } catch (e) {
    #|    console.log("inner: " + e);
    #|    throw "outer";
    #|  }
    #|} catch (e) {
    #|  console.log("outer: " + e);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"inner: inner\", \"outer: outer\"]")
}

///|
test "uncaught throw is error" {
  let mut err_msg = ""
  try {
    let _ = run_js("throw \"uncaught\"")

  } catch {
    @interpreter.JsException(val) => err_msg = val.to_string()
    _ => err_msg = "unexpected"
  }
  inspect(err_msg, content="uncaught")
}

///|
test "object literal" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|console.log(o.x + o.y);
  let output = run_output(src)
  inspect(output, content="[\"3\"]")
}

///|
test "object property assignment" {
  let src =
    #|let o = { x: 1 };
    #|o.x = 42;
    #|console.log(o.x);
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
}

///|
test "array literal" {
  let src =
    #|let a = [10, 20, 30];
    #|console.log(a[0]);
    #|console.log(a[1]);
    #|console.log(a[2]);
    #|console.log(a.length);
  let output = run_output(src)
  inspect(output, content="[\"10\", \"20\", \"30\", \"3\"]")
}

///|
test "array assignment" {
  let src =
    #|let a = [1, 2, 3];
    #|a[1] = 99;
    #|console.log(a[1]);
  let output = run_output(src)
  inspect(output, content="[\"99\"]")
}

///|
test "computed member access" {
  let src =
    #|let o = { a: 1, b: 2 };
    #|let key = "b";
    #|console.log(o[key]);
  let output = run_output(src)
  inspect(output, content="[\"2\"]")
}

///|
test "switch statement" {
  let src =
    #|let x = 2;
    #|switch (x) {
    #|  case 1:
    #|    console.log("one");
    #|    break;
    #|  case 2:
    #|    console.log("two");
    #|    break;
    #|  case 3:
    #|    console.log("three");
    #|    break;
    #|}
  let output = run_output(src)
  inspect(output, content="[\"two\"]")
}

///|
test "switch default" {
  let src =
    #|let x = 99;
    #|switch (x) {
    #|  case 1:
    #|    console.log("one");
    #|    break;
    #|  default:
    #|    console.log("other");
    #|    break;
    #|}
  let output = run_output(src)
  inspect(output, content="[\"other\"]")
}

///|
test "switch fall-through" {
  let src =
    #|let x = 1;
    #|switch (x) {
    #|  case 1:
    #|    console.log("one");
    #|  case 2:
    #|    console.log("two");
    #|    break;
    #|  case 3:
    #|    console.log("three");
    #|    break;
    #|}
  let output = run_output(src)
  inspect(output, content="[\"one\", \"two\"]")
}

///|
test "do-while loop" {
  let src =
    #|let i = 0;
    #|do {
    #|  console.log(i);
    #|  i = i + 1;
    #|} while (i < 3);
  let output = run_output(src)
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "do-while executes at least once" {
  let src =
    #|let i = 10;
    #|do {
    #|  console.log(i);
    #|} while (i < 3);
  let output = run_output(src)
  inspect(output, content="[\"10\"]")
}

///|
test "for-in object" {
  let src =
    #|let o = { a: 1, b: 2, c: 3 };
    #|let keys = "";
    #|for (let k in o) {
    #|  keys = keys + k;
    #|}
    #|console.log(keys);
  let output = run_output(src)
  inspect(output, content="[\"abc\"]")
}

///|
test "prefix increment" {
  let src =
    #|let x = 5;
    #|console.log(++x);
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"6\", \"6\"]")
}

///|
test "postfix increment" {
  let src =
    #|let x = 5;
    #|console.log(x++);
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"5\", \"6\"]")
}

///|
test "prefix decrement" {
  let src =
    #|let x = 5;
    #|console.log(--x);
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"4\", \"4\"]")
}

///|
test "compound assignment +=" {
  let src =
    #|let x = 10;
    #|x += 5;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"15\"]")
}

///|
test "compound assignment -=" {
  let src =
    #|let x = 10;
    #|x -= 3;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"7\"]")
}

///|
test "compound assignment *=" {
  let src =
    #|let x = 4;
    #|x *= 3;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"12\"]")
}

///|
test "bitwise AND" {
  let (_, result) = run_js("12 & 10")
  inspect(result, content="8")
}

///|
test "bitwise OR" {
  let (_, result) = run_js("12 | 10")
  inspect(result, content="14")
}

///|
test "bitwise XOR" {
  let (_, result) = run_js("12 ^ 10")
  inspect(result, content="6")
}

///|
test "bitwise NOT" {
  let (_, result) = run_js("~0")
  inspect(result, content="-1")
}

///|
test "left shift" {
  let (_, result) = run_js("1 << 4")
  inspect(result, content="16")
}

///|
test "right shift" {
  let (_, result) = run_js("-16 >> 2")
  inspect(result, content="-4")
}

///|
test "unsigned right shift" {
  let (_, result) = run_js("-1 >>> 0")
  inspect(result, content="4294967295")
}

///|
test "void operator" {
  let (_, result) = run_js("void 0")
  inspect(result, content="undefined")
}

///|
test "void expression" {
  let output = run_output("console.log(void 0 === undefined)")
  inspect(output, content="[\"true\"]")
}

///|
test "delete property" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|delete o.x;
    #|console.log(o.x);
  let output = run_output(src)
  inspect(output, content="[\"undefined\"]")
}

///|
test "in operator" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|console.log("x" in o);
    #|console.log("z" in o);
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "comma expression" {
  let (_, result) = run_js("1, 2, 3")
  inspect(result, content="3")
}

///|
test "typeof undeclared variable" {
  let (_, result) = run_js("typeof nonExistent")
  inspect(result, content="undefined")
}

///|
test "new expression" {
  let src =
    #|function Person(name) {
    #|  this.name = name;
    #|}
    #|let p = new Person("Alice");
    #|console.log(p.name);
  let output = run_output(src)
  inspect(output, content="[\"Alice\"]")
}

///|
test "new expression with method" {
  let src =
    #|function Counter(start) {
    #|  this.count = start;
    #|  this.inc = function() {
    #|    this.count = this.count + 1;
    #|    return this.count;
    #|  };
    #|}
    #|let c = new Counter(0);
    #|console.log(c.inc());
    #|console.log(c.inc());
  let output = run_output(src)
  inspect(output, content="[\"1\", \"2\"]")
}

///|
test "method call this binding" {
  let src =
    #|let obj = { x: 42, getX: function() { return this.x; } };
    #|console.log(obj.getX());
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
}

///|
test "string length" {
  let (_, result) = run_js("\"hello\".length")
  inspect(result, content="5")
}

///|
test "for loop with ++" {
  let src =
    #|for (let i = 0; i < 3; i++) {
    #|  console.log(i);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "type coercion arithmetic" {
  let output = run_output(
    "console.log(true + 1); console.log(null + 1); console.log(false + false)",
  )
  inspect(output, content="[\"2\", \"1\", \"0\"]")
}

///|
test "neg coercion" {
  let (_, result) = run_js("-true")
  inspect(result, content="-1")
}

// ===== Task 1G: Built-in Globals =====

///|
test "NaN global" {
  let out = run_output("console.log(NaN)")
  inspect(out[0], content="NaN")
}

///|
test "Infinity global" {
  let out = run_output("console.log(Infinity)")
  inspect(out[0], content="Infinity")
}

///|
test "undefined global" {
  let (_, result) = run_js("undefined")
  inspect(result, content="undefined")
}

///|
test "isNaN true" {
  let (_, result) = run_js("isNaN(NaN)")
  inspect(result, content="true")
}

///|
test "isNaN false" {
  let (_, result) = run_js("isNaN(42)")
  inspect(result, content="false")
}

///|
test "isNaN string coercion" {
  let (_, result) = run_js("isNaN(\"hello\")")
  inspect(result, content="true")
}

///|
test "isNaN numeric string" {
  let (_, result) = run_js("isNaN(\"123\")")
  inspect(result, content="false")
}

///|
test "isFinite true" {
  let (_, result) = run_js("isFinite(42)")
  inspect(result, content="true")
}

///|
test "isFinite infinity" {
  let (_, result) = run_js("isFinite(Infinity)")
  inspect(result, content="false")
}

///|
test "isFinite NaN" {
  let (_, result) = run_js("isFinite(NaN)")
  inspect(result, content="false")
}

///|
test "parseInt basic" {
  let (_, result) = run_js("parseInt(\"42\")")
  inspect(result, content="42")
}

///|
test "parseInt with leading text stops" {
  let (_, result) = run_js("parseInt(\"123abc\")")
  inspect(result, content="123")
}

///|
test "parseInt hex" {
  let (_, result) = run_js("parseInt(\"0xFF\")")
  inspect(result, content="255")
}

///|
test "parseInt radix" {
  let (_, result) = run_js("parseInt(\"111\", 2)")
  inspect(result, content="7")
}

///|
test "parseInt negative" {
  let (_, result) = run_js("parseInt(\"-42\")")
  inspect(result, content="-42")
}

///|
test "parseInt NaN for non-numeric" {
  let out = run_output("console.log(parseInt(\"hello\"))")
  inspect(out[0], content="NaN")
}

///|
test "parseInt empty string" {
  let out = run_output("console.log(parseInt(\"\"))")
  inspect(out[0], content="NaN")
}

///|
test "parseFloat basic" {
  let (_, result) = run_js("parseFloat(\"3.14\")")
  inspect(result, content="3.14")
}

///|
test "parseFloat integer" {
  let (_, result) = run_js("parseFloat(\"42\")")
  inspect(result, content="42")
}

///|
test "parseFloat with trailing text" {
  let (_, result) = run_js("parseFloat(\"3.14abc\")")
  inspect(result, content="3.14")
}

///|
test "parseFloat NaN" {
  let out = run_output("console.log(parseFloat(\"hello\"))")
  inspect(out[0], content="NaN")
}

///|
test "String conversion number" {
  let (_, result) = run_js("String(42)")
  inspect(result, content="42")
}

///|
test "String conversion bool" {
  let (_, result) = run_js("String(true)")
  inspect(result, content="true")
}

///|
test "String conversion null" {
  let (_, result) = run_js("String(null)")
  inspect(result, content="null")
}

///|
test "String conversion undefined" {
  let (_, result) = run_js("String(undefined)")
  inspect(result, content="undefined")
}

///|
test "Number conversion string" {
  let (_, result) = run_js("Number(\"42\")")
  inspect(result, content="42")
}

///|
test "Number conversion true" {
  let (_, result) = run_js("Number(true)")
  inspect(result, content="1")
}

///|
test "Number conversion false" {
  let (_, result) = run_js("Number(false)")
  inspect(result, content="0")
}

///|
test "Number conversion null" {
  let (_, result) = run_js("Number(null)")
  inspect(result, content="0")
}

///|
test "Number conversion non-numeric string" {
  let out = run_output("console.log(Number(\"hello\"))")
  inspect(out[0], content="NaN")
}

///|
test "Boolean truthy" {
  let (_, result) = run_js("Boolean(1)")
  inspect(result, content="true")
}

///|
test "Boolean falsy zero" {
  let (_, result) = run_js("Boolean(0)")
  inspect(result, content="false")
}

///|
test "Boolean empty string" {
  let (_, result) = run_js("Boolean(\"\")")
  inspect(result, content="false")
}

///|
test "Boolean non-empty string" {
  let (_, result) = run_js("Boolean(\"hello\")")
  inspect(result, content="true")
}

///|
test "Boolean null" {
  let (_, result) = run_js("Boolean(null)")
  inspect(result, content="false")
}

///|
test "new Error" {
  let src =
    #|var e = new Error("something went wrong");
    #|console.log(e.message);
  let out = run_output(src)
  inspect(out[0], content="something went wrong")
}

///|
test "new TypeError" {
  let src =
    #|var e = new TypeError("bad type");
    #|console.log(e.name);
  let out = run_output(src)
  inspect(out[0], content="TypeError")
}

///|
test "new RangeError" {
  let src =
    #|var e = new RangeError("out of range");
    #|console.log(e.message);
  let out = run_output(src)
  inspect(out[0], content="out of range")
}

///|
test "throw and catch Error" {
  let src =
    #|try {
    #|  throw new Error("oops");
    #|} catch (e) {
    #|  console.log(e.message);
    #|}
  let out = run_output(src)
  inspect(out[0], content="oops")
}

///|
test "Error name property" {
  let src =
    #|var e = new Error("test");
    #|console.log(e.name);
  let out = run_output(src)
  inspect(out[0], content="Error")
}

///|
test "Error no args" {
  let src =
    #|var e = new Error();
    #|console.log(e.message);
  let out = run_output(src)
  inspect(out[0], content="")
}

///|
test "parseInt with whitespace" {
  let (_, result) = run_js("parseInt(\"  42  \")")
  inspect(result, content="42")
}

///|
test "parseInt hex with radix 16" {
  let (_, result) = run_js("parseInt(\"ff\", 16)")
  inspect(result, content="255")
}

///|
test "parseFloat negative" {
  let (_, result) = run_js("parseFloat(\"-3.14\")")
  inspect(result, content="-3.14")
}

///|
test "typeof NaN" {
  let (_, result) = run_js("typeof NaN")
  inspect(result, content="number")
}

///|
test "typeof Infinity" {
  let (_, result) = run_js("typeof Infinity")
  inspect(result, content="number")
}

///|
test "NaN not equal to itself" {
  let (_, result) = run_js("NaN === NaN")
  inspect(result, content="false")
}

///|
test "Infinity arithmetic" {
  let out = run_output("console.log(Infinity + 1)")
  inspect(out[0], content="Infinity")
}

///|
test "negative Infinity" {
  let out = run_output("console.log(-Infinity)")
  inspect(out[0], content="-Infinity")
}

// ===== Phase 1 Known Issue Fixes =====

// Issue 1: to_int32 spec compliance

///|
test "to_int32 wrapping large positive" {
  let (_, result) = run_js("2147483648 | 0")
  inspect(result, content="-2147483648")
}

///|
test "to_int32 wrapping large negative" {
  let (_, result) = run_js("-2147483649 | 0")
  inspect(result, content="2147483647")
}

///|
test "to_int32 wrapping 4294967296" {
  let (_, result) = run_js("4294967296 | 0")
  inspect(result, content="0")
}

// Issue 5: parseFloat improvements

///|
test "parseFloat leading dot" {
  let (_, result) = run_js("parseFloat(\".5\")")
  inspect(result, content="0.5")
}

///|
test "parseFloat exponent" {
  let (_, result) = run_js("parseFloat(\"1e2\")")
  inspect(result, content="100")
}

///|
test "parseFloat Infinity" {
  let (_, result) = run_js("parseFloat(\"Infinity\")")
  inspect(result, content="Infinity")
}

///|
test "parseFloat negative Infinity" {
  let (_, result) = run_js("parseFloat(\"-Infinity\")")
  inspect(result, content="-Infinity")
}

// Issue 2: Error prototype chain (instanceof)

///|
test "new Error instanceof Error" {
  let (_, result) = run_js("new Error() instanceof Error")
  inspect(result, content="true")
}

///|
test "new TypeError instanceof TypeError" {
  let (_, result) = run_js("new TypeError(\"bad\") instanceof TypeError")
  inspect(result, content="true")
}

// Issue 3: for-in prototype chain

///|
test "for-in prototype chain" {
  let src =
    #|function Base() { this.a = 1; }
    #|Base.prototype.b = 2;
    #|var obj = new Base();
    #|var keys = "";
    #|for (var k in obj) { keys = keys + k; }
    #|console.log(keys);
  let output = run_output(src)
  inspect(output, content="[\"ab\"]")
}

// Issue 6: double evaluation in update/compound-assign

///|
test "update member single evaluation" {
  let src =
    #|var counter = 0;
    #|function getSide() { counter++; return { x: 10 }; }
    #|var obj = getSide();
    #|obj.x++;
    #|console.log(counter);
    #|console.log(obj.x);
  let output = run_output(src)
  inspect(output, content="[\"1\", \"11\"]")
}

///|
test "compound assign member single evaluation" {
  let src =
    #|var obj = { x: 10 };
    #|obj.x += 5;
    #|console.log(obj.x);
  let output = run_output(src)
  inspect(output, content="[\"15\"]")
}

// Issue 4: labeled break/continue

///|
test "labeled break" {
  let src =
    #|var result = "";
    #|outer: for (var i = 0; i < 3; i++) {
    #|  for (var j = 0; j < 3; j++) {
    #|    if (j === 1) break outer;
    #|    result = result + i + "" + j + ",";
    #|  }
    #|}
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"00,\"]")
}

///|
test "labeled continue" {
  let src =
    #|var result = "";
    #|outer: for (var i = 0; i < 3; i++) {
    #|  for (var j = 0; j < 3; j++) {
    #|    if (j === 1) continue outer;
    #|    result = result + i + "" + j + ",";
    #|  }
    #|}
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"00,10,20,\"]")
}
