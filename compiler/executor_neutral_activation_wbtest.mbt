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
test "bytecode spread recursion reaches the synchronous final call boundary" {
  let source = "function count(n) { if (n === 0) return 0; " +
    "return count(n - 1, ...[]) + 1; }\n" +
    "count(321, ...[]);"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_arg_spread = false
  let mut saw_call_spread = false
  for instr in lowered.main.code {
    match instr {
      ArgPushSpread(_) => saw_arg_spread = true
      CallSpread(_) => saw_call_spread = true
      _ => ()
    }
  }
  assert_true(saw_arg_spread)
  assert_true(saw_call_spread)
  let mut saw_count_child = false
  let mut saw_recursive_arg_spread = false
  let mut saw_recursive_call_spread = false
  for child in lowered.main.children {
    match child.name {
      Some(name) if name == "count" => {
        saw_count_child = true
        for instr in child.code {
          match instr {
            ArgPushSpread(_) => saw_recursive_arg_spread = true
            CallSpread(_) => saw_recursive_call_spread = true
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_true(saw_count_child)
  assert_true(saw_recursive_arg_spread)
  assert_true(saw_recursive_call_spread)
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="321")
}

///|
test "spread bytecode mutual calls complete at deep finite depth" {
  let source = "function even(n) { if (n === 0) return true; " +
    "return odd(n - 1, ...[]); }\n" +
    "function odd(n) { if (n === 0) return false; " +
    "return even(n - 1, ...[]); }\n" +
    "even(2000, ...[]);"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode calls preserve ordered owned arguments" {
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "var trace = ''; var extras = [2, 3];\n" +
    "function first() { trace = trace + 'f'; return 1; }\n" +
    "function last() { trace = trace + 'l'; return 4; }\n" +
    "function child(a, b, c, d) { return a * 1000 + b * 100 + c * 10 + d; }\n" +
    "child(first(), ...extras, last()) === 1234 && trace === 'fl';",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode iterator evaluation occurs exactly once" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var iterator_gets = 0; var next_calls = 0; var values = 0;\n" +
    "var iterable = {};\n" +
    "iterable[Symbol.iterator] = function() { iterator_gets = iterator_gets + 1; " +
    "var index = 0; return { next: function() { next_calls = next_calls + 1; " +
    "if (index === 0) { index = 1; values = values + 1; " +
    "return { value: 7, done: false }; } return { done: true }; } }; };\n" +
    "function child(value) { return value; }\n" +
    "child(...iterable) === 7 && iterator_gets === 1 && " +
    "next_calls === 2 && values === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode calls own arguments before guest mutation" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var extras = [2, 3];\n" +
    "function child(a) { arguments[0] = 9; " +
    "return a + arguments[1] + arguments[2]; }\n" +
    "var answer = child(1, ...extras);\n" +
    "answer === 14 && extras[0] === 2 && extras[1] === 3;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode final invocation keeps tree and native fallbacks" {
  let interp = @interpreter.new_interpreter()
  let _ = interp.run(
    @parser.parse("function treeAdd(value) { return value + 1; }").stmts,
  )
  interp.global.def_builtin(
    "nativeAdd",
    @runtime.make_native_func(name="nativeAdd", args => {
      match args {
        [Number(left), Number(right)] => Number(left + right)
        _ => Value::Undefined
      }
    }),
  )
  let result = run_executor_neutral_bytecode(
    interp, "treeAdd(...[2]) + nativeAdd(...[3, 4]);",
  )
  inspect(result.to_string(), content="10")
}

///|
test "spread bytecode non-receiver calls preserve strict and sloppy this" {
  let source = "var strict_seen = false; var sloppy_seen = false;\n" +
    "function strict_child() { 'use strict'; " +
    "strict_seen = this === undefined; }\n" +
    "function sloppy_child() { sloppy_seen = this === globalThis; }\n" +
    "strict_child(...[]); sloppy_child(...[]);\n" +
    "strict_seen && sloppy_seen;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread lowering keeps receiver construct and direct-eval opcodes residual" {
  let lowered = parse_bytecode_for_wb(
    "function plain() {}; var obj = { call: function() {} }; var xs = []; " +
    "plain(...xs); obj.call(...xs); obj.call(); new Object(...xs); " +
    "eval(...xs);",
  )
  let mut saw_call_spread = false
  let mut saw_receiver = false
  let mut saw_fixed_receiver = false
  let mut saw_construct = false
  let mut saw_direct_eval = false
  for instr in lowered.main.code {
    match instr {
      CallSpread(_) => saw_call_spread = true
      CallSpreadWithReceiver(_) => saw_receiver = true
      CallWithReceiver(_, _) => saw_fixed_receiver = true
      ConstructSpread(_) => saw_construct = true
      CallDirectEval(_) => saw_direct_eval = true
      _ => ()
    }
  }
  assert_true(saw_call_spread)
  assert_true(saw_receiver)
  assert_true(saw_fixed_receiver)
  assert_true(saw_construct)
  assert_true(saw_direct_eval)
}

///|
test "spread evaluation abrupt completion does not invoke or replay" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var attempts = 0; var invoked = 0;\n" +
    "function boom() { attempts = attempts + 1; throw marker; }\n" +
    "function child() { invoked = invoked + 1; }\n" +
    "function attempt() { child(...boom()); }",
  )
  let result = interp.run(
    @parser.parse(
      "var same = false;\n" +
      "try { attempt(); } catch (error) { same = error === marker; }\n" +
      "same && attempts === 1 && invoked === 0;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode normal and guest throw results clean up once" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var calls = 0;\n" +
    "function child(mode) { calls = calls + 1; " +
    "if (mode === 1) throw marker; return 7; }\n" +
    "function invoke(mode) { return child(...[mode]); }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false;\n" +
      "try { invoke(1); } catch (error) { caught = error === marker; }\n" +
      "caught && invoke(2) === 7 && calls === 2;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bounded spread throw releases before a later spread leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var entered = 0;\n" +
    "function fail() { entered = entered + 1; throw marker; }\n" +
    "function caller() { fail(...[]); }\n" +
    "function leaf() { return 42; }\n" +
    "function probe() { return leaf(...[]); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let result = interp.run_bounded(
    @parser.parse(
      "var caught = false;\n" +
      "try { caller(); } catch (error) { caught = error === marker; }\n" +
      "caught && entered === 1 ? probe() : -1;",
    ).stmts,
    policy,
  )
  inspect(result.to_string(), content="42")
}

///|
test "bounded spread rejection happens before child body" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var caller_entered = 0; var child_entered = 0;\n" +
    "function child() { child_entered = child_entered + 1; return 1; }\n" +
    "function caller() { caller_entered = caller_entered + 1; " +
    "return child(...[]); }\n" +
    "function outer() { return caller(...[]); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.run_bounded(@parser.parse("outer();").stmts, policy)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified JavaScript depth exception, got " +
        error.to_string(),
      )
    None => fail("bounded spread child must be rejected before entry")
  }
  let result = interp.run(
    @parser.parse("caller_entered === 1 && child_entered === 0;").stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode receiver recursion reaches the synchronous call boundary" {
  let interp = @interpreter.new_interpreter()
  let depth = 320
  let source = "var receiver = { count: function(n) { " +
    "if (n === 0) return 0; return this.count(n - 1) + 1; } };\n" +
    "receiver.count(" +
    depth.to_string() +
    ");"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="320")
}

///|
test "bytecode receiver spread reaches the synchronous final call boundary" {
  let source = "function step(n) { if (n === 0) return this.marker; " +
    "return 1 + this.step(n - 1, ...[]); }\n" +
    "let receiver = { marker: 0, step: step };\n" +
    "receiver.step(320, ...[]);"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_main_spread = false
  let mut saw_main_receiver_call = false
  for instr in lowered.main.code {
    match instr {
      ArgPushSpread(_) => saw_main_spread = true
      CallSpreadWithReceiver(_) => saw_main_receiver_call = true
      _ => ()
    }
  }
  assert_true(saw_main_spread)
  assert_true(saw_main_receiver_call)
  let mut saw_step_child = false
  let mut saw_child_spread = false
  let mut saw_child_receiver_call = false
  for child in lowered.main.children {
    match child.name {
      Some(name) if name == "step" => {
        saw_step_child = true
        for instr in child.code {
          match instr {
            ArgPushSpread(_) => saw_child_spread = true
            CallSpreadWithReceiver(_) => saw_child_receiver_call = true
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_true(saw_step_child)
  assert_true(saw_child_spread)
  assert_true(saw_child_receiver_call)
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "spread receiver calls preserve this identity and ordered arguments" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var receiver = { marker: 40 };\n" +
    "function read(first, second) { " +
    "return this === receiver && this.marker + first + second === 43; }\n" +
    "receiver.read = read; receiver.read(1, ...[2]);",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver mutual recursion completes deeply" {
  let source = "var left = 'left'; var right = 'right';\n" +
    "var receiver = { " +
    "left: function(n) { if (n === 0) return 1; " +
    "return this[right](n - 1, ...[]) + 1; }, " +
    "right: function(n) { if (n === 0) return 0; " +
    "return this[left](n - 1, ...[]) + 1; } };\n" +
    "receiver[left](2000, ...[]);"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_root_receiver_spread = false
  let mut child_receiver_spreads = 0
  for instr in lowered.main.code {
    match instr {
      CallSpreadWithReceiver(_) => saw_root_receiver_spread = true
      _ => ()
    }
  }
  for child in lowered.main.children {
    for instr in child.code {
      match instr {
        CallSpreadWithReceiver(_) => child_receiver_spreads += 1
        _ => ()
      }
    }
  }
  assert_true(saw_root_receiver_spread)
  assert_true(child_receiver_spreads >= 2)
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="2001")
}

///|
test "receiver spread materializes a custom iterator once in order" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var iterator_gets = 0; var next_calls = 0; var return_calls = 0; " +
    "var invoked = 0;\n" +
    "var receiver = { base: 40, read: function(first, second) { " +
    "invoked = invoked + 1; return this.base + first * 10 + second; } };\n" +
    "var iterable = {}; iterable[Symbol.iterator] = function() { " +
    "iterator_gets = iterator_gets + 1; var index = 0; return { " +
    "next: function() { next_calls = next_calls + 1; " +
    "if (index === 0) { index = 1; return { value: 1, done: false }; } " +
    "if (index === 1) { index = 2; return { value: 2, done: false }; } " +
    "return { done: true }; }, return: function() { " +
    "return_calls = return_calls + 1; return { done: true }; } }; };\n" +
    "receiver.read(...iterable) === 52 && iterator_gets === 1 && " +
    "next_calls === 3 && return_calls === 0 && invoked === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "receiver spread iterator throw preserves identity without invocation or replay" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var iterator_gets = 0; var next_calls = 0; " +
    "var return_calls = 0; var invoked = 0;\n" +
    "var receiver = { read: function() { invoked = invoked + 1; } };\n" +
    "var iterable = {}; iterable[Symbol.iterator] = function() { " +
    "iterator_gets = iterator_gets + 1; return { next: function() { " +
    "next_calls = next_calls + 1; if (next_calls === 1) " +
    "return { value: 1, done: false }; throw marker; }, " +
    "return: function() { return_calls = return_calls + 1; " +
    "return { done: true }; } }; };\n" +
    "function attempt() { receiver.read(...iterable); }\n" +
    "function leaf() { return 42; }",
  )
  let result = interp.run(
    @parser.parse(
      "var same = false;\n" +
      "try { attempt(); } catch (error) { same = error === marker; }\n" +
      "same && iterator_gets === 1 && next_calls === 2 && " +
      "return_calls === 0 && invoked === 0 && leaf() === 42;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver preparation does not replay static lookup or arguments" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var lookups = 0; var factories = 0; var invoked = 0;\n" +
    "var receiver = { base: 40 };\n" +
    "Object.defineProperty(receiver, 'read', { get: function() { " +
    "lookups = lookups + 1; return function(value) { " +
    "invoked = invoked + 1; return this.base + value; }; } });\n" +
    "function make() { factories = factories + 1; return [2]; }\n" +
    "receiver.read(...make()) === 42 && lookups === 1 && " +
    "factories === 1 && invoked === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread computed receiver preparation does not replay key or arguments" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var key_reads = 0; var factories = 0; var invoked = 0;\n" +
    "var receiver = { base: 40, read: function(value) { " +
    "invoked = invoked + 1; return this.base + value; } };\n" +
    "function key() { key_reads = key_reads + 1; return 'read'; }\n" +
    "function make() { factories = factories + 1; return [2]; }\n" +
    "receiver[key()](...make()) === 42 && key_reads === 1 && " +
    "factories === 1 && invoked === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver abrupt argument evaluation preserves the thrown value" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var attempts = 0; var invoked = 0;\n" +
    "var receiver = { read: function() { invoked = invoked + 1; } };\n" +
    "function boom() { attempts = attempts + 1; throw marker; }\n" +
    "function attempt() { receiver.read(...boom()); }",
  )
  let result = interp.run(
    @parser.parse(
      "var same = false;\n" +
      "try { attempt(); } catch (error) { same = error === marker; }\n" +
      "same && attempts === 1 && invoked === 0;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver calls clean up after guest throw and resume later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var calls = 0;\n" +
    "function child(mode) { calls = calls + 1; " +
    "if (mode === 1) throw marker; return this.base + mode; }\n" +
    "var receiver = { base: 6, child: child };\n" +
    "function invoke(mode) { return receiver.child(...[mode]); }\n" +
    "function leaf() { return 42; }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false;\n" +
      "try { invoke(1); } catch (error) { caught = error === marker; }\n" +
      "caught && invoke(2) === 8 && leaf() === 42 && calls === 2;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver logical depth rejection happens before child body" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var caller_entered = 0; var child_entered = 0;\n" +
    "function child() { child_entered = child_entered + 1; return 1; }\n" +
    "var receiver = { child: child };\n" +
    "function caller() { caller_entered = caller_entered + 1; " +
    "return receiver.child(...[]); }\n" +
    "function outer() { return caller(...[]); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.run_bounded(@parser.parse("outer();").stmts, policy)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified JavaScript depth exception, got " +
        error.to_string(),
      )
    None => fail("bounded receiver spread child must be rejected before entry")
  }
  let result = interp.run(
    @parser.parse("caller_entered === 1 && child_entered === 0;").stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver runtime abrupt fallback releases before a later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var receiver = { bad: 1 };\n" +
    "function attempt() { receiver.bad(...[]); }\n" +
    "function leaf() { return 42; }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false;\n" +
      "try { attempt(); } catch (error) { caught = true; }\n" +
      "caught && leaf() === 42;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver final invocation preserves tree and native fallbacks" {
  let interp = @interpreter.new_interpreter()
  let _ = interp.run(
    @parser.parse("function treeAdd(value) { return this.base + value; }").stmts,
  )
  interp.global.def_builtin(
    "nativeAdd",
    @runtime.make_native_func(name="nativeAdd", args => {
      match args {
        [Number(left), Number(right)] => Number(left + right)
        _ => Value::Undefined
      }
    }),
  )
  let result = run_executor_neutral_bytecode(
    interp,
    "var treeHolder = { base: 4, read: treeAdd };\n" +
    "var nativeHolder = { read: nativeAdd };\n" +
    "treeHolder.read(...[3]) + nativeHolder.read(...[4, 5]);",
  )
  inspect(result.to_string(), content="16")
}

///|
test "bytecode computed receiver mutual recursion completes deeply" {
  let interp = @interpreter.new_interpreter()
  let source = "var left = 'left'; var right = 'right';\n" +
    "var receiver = { " +
    "left: function(n) { if (n === 0) return 1; " +
    "return receiver[right](n - 1) + 1; }, " +
    "right: function(n) { if (n === 0) return 0; " +
    "return receiver[left](n - 1) + 1; } };\n" +
    "receiver[left](2000);"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="2001")
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
test "executor-neutral bytecode arrow receiver call keeps lexical this" {
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "var expected = this; var arrow = () => this;\n" +
    "var holder = { arrow: arrow }; holder.arrow() === expected;",
  )
  inspect(result.to_string(), content="true")
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
test "bounded compiled ordinary calls preserve the engine depth marker" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function count(n) { if (n === 0) return 0; return count(n - 1) + 1; }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.run_bounded(@parser.parse("count(2);").stmts, policy)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified JavaScript depth exception, got " +
        error.to_string(),
      )
    None => fail("bounded compiled recursion must reject at the depth limit")
  }
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
test "bytecode frame accepts one pending call result" {
  let interp = @interpreter.new_interpreter()
  let program = parse_bytecode_for_wb("0;")
  let frame = BytecodeFrame(program.main, interp.global, {
    strict: false,
    current_generator: None,
  })
  frame.pending_call_result = true
  @runtime.ExecutorActivationFrame::deliver_call_result(frame, Number(7.0))
  inspect(frame.stack.length(), content="1")
  match frame.peek() {
    Number(value) => inspect(value, content="7")
    _ => fail("pending call result must be pushed onto the operand stack")
  }
  let second_delivery : Error? = try {
    @runtime.ExecutorActivationFrame::deliver_call_result(frame, Number(8.0))
    None
  } catch {
    error => Some(error)
  }
  match second_delivery {
    Some(@errors.InternalError(message~)) =>
      inspect(message, content="bytecode call result has no pending consumer")
    _ => fail("duplicate call result delivery must be rejected")
  }
  inspect(frame.stack.length(), content="1")
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
test "nested receiver bytecode calls release before a later bounded leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {};\n" +
    "var receiver = { fail: function() { throw marker; } };\n" +
    "function caller() { receiver.fail(); }\n" +
    "function leaf() { return 42; }\n" +
    "function probe() { return leaf(); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let result = interp.run_bounded(
    @parser.parse(
      "var caught = false;\n" +
      "try { caller(); } catch (error) { caught = error === marker; }\n" +
      "caught ? probe() : -1;",
    ).stmts,
    policy,
  )
  inspect(result.to_string(), content="42")
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
test "bytecode construct recursion reaches the synchronous constructor boundary" {
  let source = "function Step(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Step(n - 1); " +
    "this.value = child.value + 1; }\n" +
    "new Step(320).value;"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_root_construct = false
  for instr in lowered.main.code {
    match instr {
      Construct(_, _) => saw_root_construct = true
      _ => ()
    }
  }
  assert_true(saw_root_construct)
  let mut saw_step_child = false
  let mut saw_child_construct = false
  for child in lowered.main.children {
    match child.name {
      Some(name) if name == "Step" => {
        saw_step_child = true
        for instr in child.code {
          match instr {
            Construct(_, _) => saw_child_construct = true
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_true(saw_step_child)
  assert_true(saw_child_construct)
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode mutual constructor recursion stays on the activation stack" {
  let source = "function Left(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Right(n - 1); " +
    "this.value = child.value + 1; }\n" +
    "function Right(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Left(n - 1); " +
    "this.value = child.value + 1; }\n" +
    "new Left(320).value;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode construct suspension preserves setup and completion semantics" {
  let source = "var closed = 5;\n" +
    "function C(a, b) { " +
    "this.sum = a + b + closed; " +
    "this.same = new.target === C; " +
    "if (a === 1) return { replaced: 9 }; " +
    "return 7; }\n" +
    "var kept = new C(2, 3); " +
    "var replacement = new C(1, 2); " +
    "kept.sum + (kept.same ? 100 : 0) + " +
    "(Object.getPrototypeOf(kept) === C.prototype ? 10 : 0) + " +
    "replacement.replaced;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="129")
}

///|
test "bytecode construct evaluates operands once before suspended entry" {
  let source = "var log = ''; var entered = 0;\n" +
    "function C(a, b) { entered = entered + 1; log = log + 'b'; " +
    "this.value = a + b; }\n" +
    "function ctor() { log = log + 'c'; return C; }\n" +
    "function arg(value) { log = log + value; return 1; }\n" +
    "var Target = ctor(); new Target(arg('a'), arg('z'));\n" +
    "log + ':' + entered;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="cazb:1")
}

///|
test "bytecode construct abrupt argument prevents suspended body entry" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var entered = 0; var marker = {};\n" +
    "function C(value) { entered = entered + 1; this.value = value; }\n" +
    "function boom() { throw marker; }\n" +
    "function invoke() { new C(boom()); }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false; " +
      "try { invoke(); } catch (error) { caught = error === marker; } " +
      "caught && entered === 0;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode construct keeps residual constructor families synchronous" {
  let source = "function C(x) { this.x = x; }\n" +
    "var Bound = C.bind(null, 4);\n" +
    "var proxyCalls = 0;\n" +
    "var ProxyCtor = new Proxy(C, { construct: function(target, args) { " +
    "proxyCalls = proxyCalls + 1; return { x: args[0] + 1 }; } });\n" +
    "var boundValue = new Bound();\n" +
    "var proxyValue = new ProxyCtor(5);\n" +
    "var nativeValue = new Object(7);\n" +
    "boundValue.x + proxyValue.x + proxyCalls + Number(nativeValue);"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="18")
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
// Direct calls keep the sloppy undefined/global fallback; an undefined member
// base cannot form CallWithReceiver, so primitive member normalization is
// covered by the test below.
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
test "executor-neutral primitive receiver calls normalize strict and sloppy this" {
  let lowered = parse_bytecode_for_wb("(7).receiver_730_strict();")
  let mut saw_receiver_call = false
  for instr in lowered.main.code {
    match instr {
      CallWithReceiver(_, _) => saw_receiver_call = true
      _ => ()
    }
  }
  guard saw_receiver_call else {
    fail("primitive member call must lower to CallWithReceiver")
  }
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "Number.prototype.receiver_730_strict = function() { 'use strict'; " +
    "return typeof this + ':' + String(this); };\n" +
    "Number.prototype.receiver_730_sloppy = function() { " +
    "return this instanceof Number; };\n" +
    "String.prototype.receiver_730_strict = function() { 'use strict'; " +
    "return typeof this + ':' + String(this); };\n" +
    "String.prototype.receiver_730_sloppy = function() { " +
    "return this instanceof String; };\n" +
    "(7).receiver_730_strict() + '|' + " +
    "(7).receiver_730_sloppy() + '|' + " +
    "('x').receiver_730_strict() + '|' + " +
    "('x').receiver_730_sloppy();",
  )
  inspect(result.to_string(), content="number:7|true|string:x|true")
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
test "executor-neutral foreign realm receiver call preserves this" {
  let callee_interp = @interpreter.new_interpreter()
  let caller_interp = @interpreter.new_interpreter()
  let foreign_read = run_executor_neutral_bytecode(
    callee_interp, "function read() { return this.tag; } read;",
  )
  caller_interp.global.def_builtin("foreignRead", foreign_read)
  let result = run_executor_neutral_bytecode(
    caller_interp, "var holder = { tag: 'foreign-ok', read: foreignRead }; holder.read();",
  )
  inspect(result.to_string(), content="foreign-ok")
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
test "executor-neutral fixed receiver call falls back for native targets" {
  let interp = @interpreter.new_interpreter()
  interp.global.def_builtin(
    "nativeRead",
    @runtime.make_native_func(name="nativeRead", _args => {
      Value::String_("native-ok")
    }),
  )
  let result = run_executor_neutral_bytecode(
    interp, "var holder = { read: nativeRead }; holder.read();",
  )
  inspect(result.to_string(), content="native-ok")
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
