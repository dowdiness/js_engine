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
test "bytecode comma expression returns right value" {
  let src =
    #|(0, "right");
  inspect(bytecode_compare(src), content="value:right")
}

///|
test "bytecode comma expression runs left side effects before right" {
  let src =
    #|var x = 0;
    #|(x = 1, x = x + 1);
    #|x;
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode comma in assignment expression statement returns right value" {
  let src =
    #|var x = 0;
    #|x = (1, 2);
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode nested grouped comma expressions preserve evaluation order" {
  let src =
    #|var order = "";
    #|var result = ((order = order + "a", order = order + "b"), (order = order + "c", order = order + "d"));
    #|order + ":" + result;
  inspect(bytecode_compare(src), content="value:abcd:abcd")
}

///|
test "bytecode template literal interpolates values" {
  let src =
    #|var x = 2;
    #|var y = true;
    #|`a${x + 1}b${y}c`;
  inspect(bytecode_compare(src), content="value:a3btruec")
}

///|
test "bytecode template literal converts substitutions before later expressions" {
  let src =
    #|var log = "";
    #|var f = function() {};
    #|f.toString = function() { log = log + "s"; return "F"; };
    #|var result = `${f}${(log = log + "e", "E")}`;
    #|result + ":" + log;
  inspect(bytecode_compare(src), content="value:FE:se")
}

///|
test "bytecode template literal captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = "cap";
    #|  return function() { return `:${x}:`; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value::cap:")
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
test "bytecode ternary uses truthiness and returns selected branch" {
  let src =
    #|var a = 0 ? "bad" : "zero";
    #|var b = "x" ? "string" : "bad";
    #|a + "," + b;
  inspect(bytecode_compare(src), content="value:zero,string")
}

///|
test "bytecode ternary skips unselected branch side effects" {
  let src =
    #|var hits = 0;
    #|var a = true ? (hits = hits + 1) : (hits = hits + 100);
    #|var b = false ? (hits = hits + 1000) : (hits = hits + 10);
    #|a + "," + b + "," + hits;
  inspect(bytecode_compare(src), content="value:1,11,11")
}

///|
test "bytecode ternary expression statement updates completion" {
  let src =
    #|false ? "then" : "else";
  inspect(bytecode_compare(src), content="value:else")
}

///|
test "bytecode unary numeric logical and bitwise operators" {
  let src =
    #|var x = "2";
    #|(-x) + "," + (+true) + "," + (!0) + "," + (~1);
  inspect(bytecode_compare(src), content="value:-2,1,true,-2")
}

///|
test "bytecode void evaluates operand effects and yields undefined" {
  let src =
    #|var x = 0;
    #|var r = void (x = 42);
    #|(r === undefined) + "," + x;
  inspect(bytecode_compare(src), content="value:true,42")
}

///|
test "bytecode unary captured vars use environment fallback" {
  let src =
    #|function outer() {
    #|  var x = 2;
    #|  return function() { return -x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:-2")
}

///|
test "bytecode rejects delete operator until delete semantics are shared" {
  let src =
    #|var xs = [1];
    #|delete xs[0];
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: delete operator",
  )
}

///|
test "bytecode rejects typeof operator until reference semantics are shared" {
  let src =
    #|typeof missing;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: typeof operator",
  )
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
test "bytecode member assignment writes through runtime property semantics" {
  let src =
    #|var xs = [];
    #|xs.label = 3;
    #|xs.label = xs.label + 4;
    #|xs.label;
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode computed assignment preserves object key value order" {
  let src =
    #|var log = "";
    #|var xs = [];
    #|function obj() { log = log + "o"; return xs; }
    #|function key() { log = log + "k"; return 0; }
    #|function val() { log = log + "v"; return 9; }
    #|obj()[key()] = val();
    #|log + ":" + xs[0];
  inspect(bytecode_compare(src), content="value:okv:9")
}

///|
test "bytecode member assignment null receiver throws like interpreter" {
  let src =
    #|var target = null;
    #|target.x = 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot set properties of null (setting 'x')",
  )
}

///|
test "bytecode computed assignment captures outer key binding" {
  let src =
    #|function outer() {
    #|  var key = 0;
    #|  return function(xs) {
    #|    xs[key] = 5;
    #|    return xs[0];
    #|  };
    #|}
    #|outer()([]);
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode top-level this resolves global object" {
  let src =
    #|this === globalThis;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode this uses call receiver and sloppy global fallback" {
  let src =
    #|var obj = [];
    #|obj.x = 4;
    #|obj.get = function() { return this.x; };
    #|function plain() { return this === globalThis; }
    #|obj.get() + "," + plain();
  inspect(bytecode_compare(src), content="value:4,true")
}

///|
test "bytecode strict function call keeps undefined this" {
  let src =
    #|function strictThis() {
    #|  "use strict";
    #|  return this === undefined;
    #|}
    #|strictThis();
  inspect(bytecode_compare(src), content="value:true")
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
test "bytecode in operator finds own array index property" {
  let src =
    #|var xs = [10];
    #|0 in xs;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode in operator walks array prototype chain" {
  let src =
    #|"push" in [];
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode in operator rejects primitive rhs like interpreter" {
  let src =
    #|"x" in 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot use 'in' operator to search for 'x' in number",
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
