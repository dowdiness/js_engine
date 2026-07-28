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
