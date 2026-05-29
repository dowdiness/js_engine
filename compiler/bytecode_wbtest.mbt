///|
fn parse_bytecode_for_wb(src : String) -> BytecodeProgram {
  let prog = @parser.parse(src) catch { _ => abort("parse raised") }
  compile_script_to_bytecode(prog.stmts) catch {
    _ => abort("bytecode compile raised")
  }
}

///|
test "bytecode uses local slots for function params and vars" {
  let src =
    #|function f(a) {
    #|  var b = a + 1;
    #|  return b;
    #|}
    #|f(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["a", "b"])
}

///|
test "bytecode omits captured vars from local slots" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  return function() { return b; };
    #|}
    #|outer(1)();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["a"])
}

///|
test "bytecode lowers unary minus to a unary value instruction" {
  let bytecode = parse_bytecode_for_wb("var x = -1;")
  let mut saw_unary = false
  for instr in bytecode.main.code {
    match instr {
      UnaryValueOp(Neg, _) => saw_unary = true
      _ => ()
    }
  }
  guard saw_unary else { abort("expected unary value op") }
}

///|
test "bytecode lowers template literals to append instructions" {
  let bytecode = parse_bytecode_for_wb("var x = 1; `a${x}b`;")
  let mut saw_template = false
  for instr in bytecode.main.code {
    match instr {
      AppendTemplate("b") => saw_template = true
      _ => ()
    }
  }
  guard saw_template else { abort("expected template append instruction") }
}

///|
test "bytecode lowers regex literals to a runtime regexp instruction" {
  let bytecode = parse_bytecode_for_wb("var r = /a/i;")
  let mut saw_regexp = false
  for instr in bytecode.main.code {
    match instr {
      MakeRegExp("a", "i") => saw_regexp = true
      _ => ()
    }
  }
  guard saw_regexp else { abort("expected regexp instruction") }
}

///|
test "bytecode lowers simple object literals to a make object instruction" {
  let bytecode = parse_bytecode_for_wb("var o = { a: 1, b: 2 };")
  let mut saw_object = false
  for instr in bytecode.main.code {
    match instr {
      MakeObject(keys) => {
        saw_object = true
        json_inspect(keys, content=["a", "b"])
      }
      _ => ()
    }
  }
  guard saw_object else { abort("expected make object instruction") }
}

///|
test "bytecode lowers this expressions to a dedicated load instruction" {
  let bytecode = parse_bytecode_for_wb("function f() { return this; } f();")
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_this = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadThis => saw_this = true
      _ => ()
    }
  }
  guard saw_this else { abort("expected load this instruction") }
}

///|
test "bytecode treats names inside nested unary expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return -x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested template expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return `${x}`; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested object literals as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return { value: x }.value; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers member and computed assignments to property set instructions" {
  let src =
    #|var xs = [];
    #|xs.foo = 1;
    #|xs[0] = 2;
  let bytecode = parse_bytecode_for_wb(src)
  let mut saw_property_set = false
  let mut saw_computed_set = false
  for instr in bytecode.main.code {
    match instr {
      SetProperty("foo", _) => saw_property_set = true
      SetComputed(_) => saw_computed_set = true
      _ => ()
    }
  }
  guard saw_property_set else { abort("expected property set instruction") }
  guard saw_computed_set else { abort("expected computed set instruction") }
}

///|
test "bytecode lowers new expressions to construct instructions" {
  let bytecode = parse_bytecode_for_wb("function C() {} new C();")
  let mut saw_construct = false
  for instr in bytecode.main.code {
    match instr {
      Construct(0, _) => saw_construct = true
      _ => ()
    }
  }
  guard saw_construct else { abort("expected construct instruction") }
}

///|
test "bytecode treats names inside nested computed assignments as captured" {
  let src =
    #|function outer() {
    #|  var key = 0;
    #|  return function(xs) { xs[key] = 1; };
    #|}
    #|outer()([]);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}
