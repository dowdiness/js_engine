///|
fn run_executor_neutral_bytecode(
  interp : Interpreter,
  source : String,
) -> Value raise Error {
  parse_bytecode_for_wb(source).run(interp)
}

///|
test "executor-neutral bytecode function keeps a classifiable runtime payload" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(interp, "function retained() {}")
  match interp.global.get("retained") {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
      inspect(executable.name(), content="retained")
    _ => fail("bytecode function must expose the neutral executor payload")
  }
}

///|
test "executor-neutral bytecode arrow keeps a classifiable runtime payload" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "var retainedArrow = (value) => value + 1;",
  )
  match interp.global.get("retainedArrow") {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
      inspect(executable.name(), content="")
    _ => fail("bytecode arrow must expose the neutral executor payload")
  }
}

///|
test "executor-neutral bytecode method activation preserves receiver" {
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "function add(x) { return this.base + x; }\n" +
    "var holder = { base: 2, add: add };\n" +
    "holder.add(3);",
  )
  inspect(result.to_string(), content="5")
}

///|
test "ordinary bytecode recursive calls complete at finite depth" {
  let interp = @interpreter.new_interpreter()
  let depth = 97
  let source = "function count(n) { if (n === 0) return 0; return count(n - 1) + 1; }\n" +
    "count(" +
    depth.to_string() +
    ");"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="97")
}

///|
test "ordinary bytecode mutual calls complete at deep finite depth" {
  let interp = @interpreter.new_interpreter()
  let source = "function even(n) { if (n === 0) return true; return odd(n - 1); }\n" +
    "function odd(n) { if (n === 0) return false; return even(n - 1); }\n" +
    "even(2000);"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="true")
}

///|
test "ordinary bytecode arrow calls complete at deep finite depth" {
  let interp = @interpreter.new_interpreter()
  let source = "var count = (n) => n === 0 ? 0 : count(n - 1) + 1;\n" +
    "count(2000);"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="2000")
}

///|
test "tree adapter trampolines nested ordinary bytecode calls" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function count(n) { if (n === 0) return 0; return count(n - 1) + 1; }",
  )
  let result = interp.run(@parser.parse("count(2000);").stmts)
  inspect(result.to_string(), content="2000")
}

///|
test "ordinary bytecode call consumes its result once at the advanced IP" {
  let interp = @interpreter.new_interpreter()
  let source = "var calls = 0;\n" +
    "function child() { calls = calls + 1; return 2; }\n" +
    "function caller() { return child() + calls; }\n" +
    "caller();"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="3")
}

///|
test "nested ordinary bytecode calls own child arguments" {
  let interp = @interpreter.new_interpreter()
  let source = "function child(value) { arguments[0] = 7; " +
    "return value + arguments.length; }\n" +
    "function caller() { return child(1, 2); }\n" +
    "caller();"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="9")
}

///|
test "nested ordinary bytecode calls preserve guest throw identity" {
  let interp = @interpreter.new_interpreter()
  let source = "var marker = {};\n" +
    "function child() { throw marker; }\n" +
    "function caller() { child(); }"
  let _ = run_executor_neutral_bytecode(interp, source)
  let result = interp.run(
    @parser.parse("try { caller(); } catch (error) { error === marker; }").stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "ordinary bytecode call normalizes fallthrough and arrow expression results" {
  let interp = @interpreter.new_interpreter()
  let source = "function noResult() { var local = 1; }\n" +
    "var arrow = () => 3;\n" +
    "noResult(); arrow();"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="3")
}

///|
test "executor-neutral bytecode activation preserves construct and new.target" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function C(x) { this.x = x; this.same = new.target === C; }",
  )
  let result = interp.run(
    @parser.parse("var value = new C(7); value.x + (value.same ? 1 : 0);").stmts,
  )
  inspect(result.to_string(), content="8")
}

///|
test "executor-neutral bytecode activation preserves arguments aliasing" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function f(a) { arguments[0] = 7; return a + arguments.length; }",
  )
  let result = interp.run(@parser.parse("f(1, 2);").stmts)
  inspect(result.to_string(), content="9")
}

///|
test "executor-neutral bytecode activation preserves strict and sloppy this" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "function sloppy() { return this === globalThis; }\n" +
    "function strict() { 'use strict'; return this === undefined; }",
  )
  let result = interp.run(@parser.parse("sloppy() && strict();").stmts)
  inspect(result.to_string(), content="true")
}

///|
test "executor-neutral mixed tree to bytecode call preserves receiver" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function bytecodeAdd(x) { return this.base + x; }",
  )
  let tree = @parser.parse("bytecodeAdd.call({ base: 4 }, 3);")
  let result = interp.run(tree.stmts)
  inspect(result.to_string(), content="7")
}

///|
test "executor-neutral mixed bytecode to tree call preserves return" {
  let interp = @interpreter.new_interpreter()
  let tree = @parser.parse("function treeAdd(x) { return this.base + x; }")
  let _ = interp.run(tree.stmts)
  let result = run_executor_neutral_bytecode(
    interp, "treeAdd.call({ base: 5 }, 3);",
  )
  inspect(result.to_string(), content="8")
}

///|
test "executor-neutral bytecode to native call preserves arguments" {
  let interp = @interpreter.new_interpreter()
  interp.global.def_builtin(
    "nativeAdd",
    @runtime.make_native_func(name="nativeAdd", args => {
      match args {
        [Number(left), Number(right)] => Number(left + right)
        _ => Undefined
      }
    }),
  )
  let result = run_executor_neutral_bytecode(interp, "nativeAdd(2, 3);")
  inspect(result.to_string(), content="5")
}

///|
test "executor-neutral foreign constructor keeps callee realm prototype" {
  let callee_interp = @interpreter.new_interpreter()
  let caller_interp = @interpreter.new_interpreter()
  let ctor_value = run_executor_neutral_bytecode(
    callee_interp, "function C() {} C.prototype = 1; C;",
  )
  caller_interp.global.def_builtin("ForeignCtor", ctor_value)
  let instance = caller_interp.run(@parser.parse("new ForeignCtor();").stmts)
  guard instance is Object(instance_data) else {
    fail("expected executor-neutral constructor to return an object")
  }
  let callee_proto = @runtime.get_obj_proto(
    realm_state=Some(callee_interp.realm_state),
  )
  let caller_proto = @runtime.get_obj_proto(
    realm_state=Some(caller_interp.realm_state),
  )
  assert_true(physical_equal(instance_data.prototype, callee_proto))
  assert_false(physical_equal(instance_data.prototype, caller_proto))
}

///|
test "executor-neutral bytecode throw is caught by tree caller" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function bytecodeThrow() { throw 9; }",
  )
  let tree = @parser.parse(
    "try { bytecodeThrow(); } catch (error) { error + 1; }",
  )
  let result = interp.run(tree.stmts)
  inspect(result.to_string(), content="10")
}
