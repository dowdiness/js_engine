///|
const BYTECODE_CLOSURE_FACTORY_PROGRAM : String =
  #|function makeCounter(start) {
  #|  var count = start;
  #|  return function() {
  #|    count = count + 1;
  #|    return count;
  #|  };
  #|}
  #|var counters = [];
  #|for (var i = 0; i < 1000; i++) {
  #|  counters.push(makeCounter(i));
  #|}
  #|var total = 0;
  #|for (var i = 0; i < 1000; i++) {
  #|  total = total + counters[i]();
  #|}
  #|total;

///|
const BYTECODE_PIPELINE_EXEC_PROGRAM : String =
  #|(function() {
  #|  function makeCounter(start) {
  #|    var count = start;
  #|    return function() {
  #|      count = count + 1;
  #|      return count;
  #|    };
  #|  }
  #|  var counters = [];
  #|  for (var i = 0; i < 1000; i++) {
  #|    counters.push(makeCounter(i));
  #|  }
  #|  var total = 0;
  #|  for (var i = 0; i < 1000; i++) {
  #|    total = total + counters[i]();
  #|  }
  #|  return total;
  #|})();

///|
fn bytecode_interpreter_outcome(src : String) -> String {
  try {
    let prog = @parser.parse(src)
    let interp = @interpreter.new_interpreter()
    "value:" + interp.run(prog.stmts).to_string()
  } catch {
    @runtime.JsException(value) => "throw:" + value.to_string()
    err => "error:" + err.to_string()
  }
}

///|
fn bytecode_outcome(src : String) -> String {
  try {
    let prog = @parser.parse(src)
    let interp = @interpreter.new_interpreter()
    let bytecode = compile_script_to_bytecode(prog.stmts)
    "value:" + bytecode.run(interp).to_string()
  } catch {
    @runtime.JsException(value) => "throw:" + value.to_string()
    err => "error:" + err.to_string()
  }
}

///|
fn bytecode_compare(src : String) -> String {
  let expected = bytecode_interpreter_outcome(src)
  let actual = bytecode_outcome(src)
  if actual == expected {
    actual
  } else {
    "expected \{expected}; got \{actual}"
  }
}

///|
test "bytecode constants locals and binary ops" {
  let src =
    #|var x = 1;
    #|x = x + 2;
    #|x;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode logical and skips rhs and returns original falsy operand" {
  let src =
    #|var rhs = 0;
    #|var result = 0 && (rhs = 1);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:0,0")
}

///|
test "bytecode logical and evaluates rhs and returns rhs when lhs is truthy" {
  let src =
    #|var rhs = 0;
    #|var result = 2 && (rhs = 5);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:5,5")
}

///|
test "bytecode logical or skips rhs and returns original truthy operand" {
  let src =
    #|var rhs = 0;
    #|var result = "left" || (rhs = 1);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:left,0")
}

///|
test "bytecode logical or evaluates rhs and returns rhs when lhs is falsy" {
  let src =
    #|var rhs = 0;
    #|var result = false || (rhs = 7);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:7,7")
}

///|
test "bytecode nullish coalescing only skips non-nullish lhs values" {
  let src =
    #|var side = 0;
    #|var a = 0 ?? (side = side + 1);
    #|var b = false ?? (side = side + 10);
    #|var c = "" ?? (side = side + 100);
    #|var d = null ?? (side = side + 1000);
    #|var e = undefined ?? (side = side + 10000);
    #|a + "," + b + "," + c + "," + d + "," + e + "," + side;
  inspect(bytecode_compare(src), content="value:0,false,,1000,11000,11000")
}

///|
test "bytecode jumps and branch completion" {
  let src =
    #|var x = 0;
    #|if (1 < 2) {
    #|  x = 3;
    #|} else {
    #|  x = 4;
    #|}
    #|x;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode calls and return" {
  let src =
    #|function add(a, b) {
    #|  return a + b;
    #|}
    #|add(2, 3);
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode hoists nested function declarations" {
  let src =
    #|(function() {
    #|  return f();
    #|  function f() { return 7; }
    #|})();
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode function declaration identity is stable after hoist" {
  let src =
    #|(function() {
    #|  var a = f;
    #|  function f() { return 1; }
    #|  var b = f;
    #|  return a === b;
    #|})();
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode hoists captured var bindings to undefined" {
  let src =
    #|(function() {
    #|  var f = function() { return x; };
    #|  return f();
    #|  var x = 1;
    #|})();
  inspect(bytecode_compare(src), content="value:undefined")
}

///|
test "bytecode mirrors top-level var initialization to global object" {
  let src =
    #|var x = 1;
    #|globalThis.x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode statement completion matches interpreter for declarations and skipped branches" {
  inspect(bytecode_compare("1; var x = 2;"), content="value:undefined")
  inspect(bytecode_compare("1; if (false) { 2; }"), content="value:undefined")
  inspect(
    bytecode_compare("1; while (false) { 2; }"),
    content="value:undefined",
  )
}

///|
test "bytecode sets function names for anonymous assignment targets" {
  let src =
    #|var f = function() {};
    #|f.name;
  inspect(bytecode_compare(src), content="value:f")
}

///|
test "bytecode reuses runtime name assignment semantics" {
  let src =
    #|x = 1;
    #|globalThis.x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode resolves computed callees before arguments" {
  let src =
    #|var fns = [
    #|  function() { return "old"; },
    #|  function() { return "new"; }
    #|];
    #|function arg() {
    #|  fns.shift();
    #|  return 0;
    #|}
    #|fns[0](arg());
  inspect(bytecode_compare(src), content="value:old")
}

///|
test "bytecode rejects named function expressions until self-name binding is implemented" {
  let src =
    #|var f = function g() { return g; };
    #|f();
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: named function expression",
  )
}

///|
test "bytecode rejects arguments object until function call setup supports it" {
  let src =
    #|function f() {
    #|  return arguments[0];
    #|}
    #|f(42);
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: arguments object",
  )
}

///|
test "bytecode rejects console member special case until runtime helper is shared" {
  let src =
    #|console.log(1);
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: console member",
  )
}

///|
test "bytecode leaves captured vars in environment fallback" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  return function() { return b; };
    #|}
    #|outer(1)();
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode closure captures parent binding" {
  let src =
    #|function makeCounter(start) {
    #|  var count = start;
    #|  return function() {
    #|    count = count + 1;
    #|    return count;
    #|  };
    #|}
    #|var counter = makeCounter(2);
    #|counter();
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode hoists function body lexical bindings before execution" {
  let src =
    #|var x = 2;
    #|function f() {
    #|  return x;
    #|  let x = 1;
    #|}
    #|f();
  inspect(
    bytecode_compare(src),
    content="throw:ReferenceError: Cannot access 'x' before initialization",
  )
}

///|
test "bytecode rejects direct eval until caller-env semantics are implemented" {
  let src =
    #|var x = 1;
    #|eval("x = 2");
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: direct eval call",
  )
}

///|
test "bytecode rejects block lexical declarations until block envs are implemented" {
  let src =
    #|var x = 1;
    #|{
    #|  let x = 2;
    #|}
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: block lexical declaration",
  )
}

///|
test "bytecode rejects for lexical initializers until loop scoping is implemented" {
  let src =
    #|for (let i = 0; i < 1; i = i + 1) {
    #|}
    #|i;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: for lexical initializer",
  )
}

///|
test "bytecode rejects control-flow var declarations until completion tracking is implemented" {
  let src =
    #|if (true) {
    #|  1;
    #|  var x = 2;
    #|}
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: control-flow var declaration",
  )
}

///|
test "bytecode rejects control-flow function declarations until block semantics are implemented" {
  let src =
    #|if (true) {
    #|  function f() { return 1; }
    #|}
    #|f();
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: control-flow function declaration",
  )
}

///|
test "bytecode rejects in operator until object-key semantics are implemented" {
  let src =
    #|"x" in [];
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: in operator",
  )
}

///|
test "bytecode rejects instanceof operator until runtime helper is shared" {
  let src =
    #|1 instanceof function() {};
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: instanceof operator",
  )
}

///|
test "bytecode closure factory workload" {
  inspect(
    bytecode_compare(BYTECODE_CLOSURE_FACTORY_PROGRAM),
    content="value:500500",
  )
}

///|
test "bytecode pipeline evaluate workload" {
  inspect(
    bytecode_compare(BYTECODE_PIPELINE_EXEC_PROGRAM),
    content="value:500500",
  )
}
