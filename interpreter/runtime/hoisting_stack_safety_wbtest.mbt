///|
fn hoisting_test_seed() -> (@token.Loc, @ast.Expr?) raise Error {
  match @parser.parse("var seed;").stmts[0] {
    @ast.Stmt::VarDecl(_, _, init, loc) => (loc, init)
    _ => abort("expected variable declaration")
  }
}

///|
fn deeply_wrapped_stmt(stmt : @ast.Stmt, depth : Int) -> @ast.Stmt raise Error {
  let (loc, _) = hoisting_test_seed()
  let mut nested = stmt
  for _ in 0..<depth {
    nested = @ast.Stmt::Block([nested], loc)
  }
  nested
}

///|
test "Task 4C: eval names have exact static-semantics parity" {
  let source =
    #|var top;
    #|label: function labeled() {}
    #|{ var block; function hidden_block() {} }
    #|if (cond) { var then_name; } else { var else_name; }
    #|for (var init; cond; step) { var body; }
    #|switch (x) { case 0: var case_name; default: var default_name; }
    #|try { var tried; } catch (e) { var caught; } finally { var finished; }
    #|with (scope) { var with_name; }
    #|export var exported;
    #|function boundary() { var hidden_function; }
    #|class Boundary { method() { var hidden_class; } }
  let parsed = @parser.parse(source)
  assert_eq(
    collect_eval_var_names(parsed.stmts),
    @static_semantics.collect_var_declared_names(parsed.stmts),
  )
}

///|
test "post-parse stack safety: deep eval name collection and global preflight walk" {
  let (loc, init) = hoisting_test_seed()
  let nested = deeply_wrapped_stmt(
    @ast.Stmt::VarDecl(VarKind, "deep_var", init, loc),
    4096,
  )
  json_inspect(collect_eval_var_names([nested]), content=["deep_var"])
  let names : Array[String] = []
  walk_var_scoped_names(nested, name => names.push(name))
  json_inspect(names, content=["deep_var"])
}

///|
test "post-parse stack safety: deep actual var hoisting" {
  let (loc, init) = hoisting_test_seed()
  let nested = deeply_wrapped_stmt(
    @ast.Stmt::VarDecl(VarKind, "deep_var", init, loc),
    4096,
  )
  let env = Environment::new()
  hoist_var_declarations_from_stmt(nested, env)
  inspect(env.bindings.contains("deep_var"), content="true")
}

///|
test "post-parse stack safety: deep TDZ statement wrappers" {
  let (loc, init) = hoisting_test_seed()
  let mut nested = @ast.Stmt::VarDecl(LetKind, "deep_let", init, loc)
  for _ in 0..<4096 {
    nested = @ast.Stmt::StmtList([nested], loc)
  }
  let env = Environment::new()
  hoist_block_tdz([nested], env)
  inspect(env.bindings.contains("deep_let"), content="true")
}

///|
test "Task 4C: var preflight preserves shallow order and first error" {
  let parsed = @parser.parse("var first; var second;")
  let names : Array[String] = []
  for stmt in parsed.stmts {
    walk_var_scoped_names(stmt, name => names.push(name))
  }
  json_inspect(names, content=["first", "second"])

  let visited : Array[String] = []
  let result : Result[Unit, Error] = Ok(
    walk_var_scoped_names(
      @ast.Stmt::StmtList(
        parsed.stmts,
        match parsed.stmts[0] {
          @ast.Stmt::VarDecl(_, _, _, loc) => loc
          _ => abort("expected variable declaration")
        },
      ),
      name => {
        visited.push(name)
        raise @errors.TypeError(message="first diagnostic: \{name}")
      },
    ),
  ) catch {
    error => Err(error)
  }
  debug_inspect(
    result,
    content="Err(TypeError(message=\"first diagnostic: first\"))",
  )
  json_inspect(visited, content=["first"])
}

///|
test "global declaration diagnostics interpolate the rejected function name" {
  let interp = Interpreter::new()
  match interp.global_this {
    Object(data) => {
      data.bag.properties["blocked"] = Undefined
      data.bag.descriptors["blocked"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => fail("expected global object")
  }
  let caught : Error? = try {
    check_global_function_declarations(interp, ["blocked"])
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(message~)) =>
      assert_eq(
        message, "Cannot declare global function 'blocked': property is non-configurable",
      )
    Some(error) => fail("expected TypeError, got " + error.to_string())
    None => fail("expected global function declaration rejection")
  }
}

///|
test "global declaration diagnostics interpolate the rejected var name" {
  let interp = Interpreter::new()
  match interp.global_this {
    Object(data) => data.extensible = false
    _ => fail("expected global object")
  }
  let caught : Error? = try {
    check_global_var_declarations(interp, [], ["blocked"])
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(message~)) =>
      assert_eq(
        message, "Cannot declare global var 'blocked': global object is non-extensible",
      )
    Some(error) => fail("expected TypeError, got " + error.to_string())
    None => fail("expected global var declaration rejection")
  }
}

///|
test "compiled script preparation rejects an unsettled early-error boundary" {
  let interp = Interpreter::new()
  let preparation = CompiledScriptPreparation(
    strict=false,
    var_names=[],
    function_names=[],
    lexical_bindings=[],
  )
  let caught : Error? = try {
    interp.apply_compiled_script_preparation(preparation)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.InternalError(message~)) =>
      assert_eq(
        message, "unsettled CompiledScriptPreparation cannot be applied",
      )
    Some(error) => fail("expected InternalError, got " + error.to_string())
    None => fail("expected unsettled preparation rejection")
  }
}

///|
fn annex_b_tagged_names(
  source : String,
  names : Array[String],
  excluded? : @set.Set[String] = Default::default(),
) -> Array[String] raise Error {
  let parsed = @parser.parse(source)
  let interp = Interpreter::new()
  let env = Environment::new()
  hoist_eval_annex_b_candidates(
    interp,
    parsed.stmts,
    env,
    Default::default(),
    excluded~,
  )
  names.filter(name => {
    match env.bindings.get(name) {
      Some(binding) => binding.annex_b_hoisted
      None => false
    }
  })
}

///|
test "Task 4D: Annex B candidate effects follow source traversal order" {
  let source =
    #|{ function sibling_first() {} function sibling_second() {} }
    #|if (false) function if_then() {} else function if_else() {}
    #|switch (0) {
    #|  case 0: function case_first() {}
    #|  default: function case_second() {}
    #|}
    #|try { function try_first() {} }
    #|catch (e) { function catch_second() {} }
    #|finally { function finally_third() {} }
  let parsed = @parser.parse(source)
  let interp = Interpreter::new()
  let env = Environment::new()
  hoist_eval_annex_b_candidates(interp, parsed.stmts, env, Default::default())
  json_inspect(env.bindings.keys().collect(), content=[
    "sibling_first", "sibling_second", "if_then", "if_else", "case_first", "case_second",
    "try_first", "catch_second", "finally_third",
  ])
}

///|
test "Task 4D: StmtList and export preserve incoming block context" {
  let parsed = @parser.parse(
    "function plain() {} label: function labeled() {} export function exported() {}",
  )
  guard parsed.stmts[2]
    is @ast.Stmt::ExportNamedDecl(Some(exported), _, _, _, _) else {
    abort("expected exported declaration")
  }
  let (loc, _) = hoisting_test_seed()
  let interp = Interpreter::new()
  let top_env = Environment::new()
  hoist_eval_annex_b_candidates(
    interp,
    [
      @ast.Stmt::StmtList([parsed.stmts[0]], loc),
      parsed.stmts[1],
      parsed.stmts[2],
    ],
    top_env,
    Default::default(),
  )
  json_inspect(
    ["plain", "labeled", "exported"].map(name => {
      top_env.bindings
      .get(name)
      .map_or(false, binding => binding.annex_b_hoisted)
    }),
    content=[false, true, false],
  )

  let block_env = Environment::new()
  hoist_eval_annex_b_candidates(
    interp,
    [
      @ast.Stmt::Block(
        [
          @ast.Stmt::StmtList([parsed.stmts[0]], loc),
          @ast.Stmt::ExportNamedDecl(Some(exported), [], None, LexNormal, loc),
        ],
        loc,
      ),
    ],
    block_env,
    Default::default(),
  )
  json_inspect(
    ["plain", "exported"].map(name => {
      block_env.bindings
      .get(name)
      .map_or(false, binding => binding.annex_b_hoisted)
    }),
    content=[true, true],
  )
}

///|
test "Task 4D: loop-head frame does not leak to later siblings" {
  let source =
    #|for (let loop_name = 0; false;) { function loop_name() {} }
    #|if (false) function loop_name() {}
    #|for (let body_only = 0; false;) { function body_only() {} }
    #|if (false) function later() {}
  json_inspect(
    annex_b_tagged_names(source, ["loop_name", "body_only", "later"]),
    content=["loop_name", "later"],
  )
}

///|
test "Task 4D: excluded candidate does not suppress later eligible candidate" {
  let excluded : @set.Set[String] = Default::default()
  excluded.add("parameter")
  json_inspect(
    annex_b_tagged_names(
      "{ function parameter() {} function eligible() {} }",
      ["parameter", "eligible"],
      excluded~,
    ),
    content=["eligible"],
  )
}

///|
test "Task 4D: try catch and finally lexical frames have distinct lifetimes" {
  let source =
    #|try {
    #|  let try_name;
    #|  { function try_name() {} }
    #|} catch (identifier) {
    #|  function identifier() {}
    #|  function try_name() {}
    #|  let catch_name;
    #|  { function catch_name() {} }
    #|} finally {
    #|  function catch_name() {}
    #|  let finally_name;
    #|  { function finally_name() {} }
    #|}
    #|try {} catch ({ destructured }) { function destructured() {} }
  json_inspect(
    annex_b_tagged_names(source, [
      "try_name", "identifier", "catch_name", "finally_name", "destructured",
    ]),
    content=["try_name", "identifier", "catch_name"],
  )
}

///|
test "Task 4D: Annex B shallow frame and boundary behavior" {
  let source =
    #|{ function block() {} }
    #|label: function labeled() {}
    #|for (let loop_head = 0; false;) { function loop_head() {} }
    #|switch (0) {
    #|  case 0: let shared; break;
    #|  default: function shared() {} function switched() {}
    #|}
    #|try { function tried() {} }
    #|catch (identifier) { function identifier() {} }
    #|finally { function finished() {} }
    #|try {} catch ({ destructured }) { function destructured() {} }
    #|with ({}) { function withed() {} }
    #|function boundary() { { function hidden_function() {} } }
    #|class Boundary { method() { function hidden_class() {} } }
  json_inspect(
    annex_b_tagged_names(source, [
      "block", "labeled", "loop_head", "shared", "switched", "tried", "identifier",
      "finished", "destructured", "withed", "hidden_function", "hidden_class",
    ]),
    content=[
      "block", "labeled", "switched", "tried", "identifier", "finished", "withed",
    ],
  )
}

///|
test "post-parse stack safety: deep Annex B candidates behind false control flow" {
  let parsed = @parser.parse("if (false) function deep_candidate() {}")
  guard parsed.stmts[0] is @ast.Stmt::IfStmt(test_expr, candidate, None, loc) else {
    abort("expected if statement")
  }
  let mut nested = candidate
  for _ in 0..<4096 {
    nested = @ast.Stmt::IfStmt(test_expr, nested, None, loc)
  }
  let interp = Interpreter::new()
  let env = Environment::new()
  hoist_eval_annex_b_candidates(interp, [nested], env, Default::default())
  debug_inspect(
    env.bindings.get("deep_candidate").map(binding => binding.annex_b_hoisted),
    content="Some(true)",
  )
}
