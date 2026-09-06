///|
fn assert_try_block_result(source : String, expected : String) -> Unit raise {
  let stmts = @parser.parse(source).stmts
  let tree = @interpreter.new_interpreter().run(stmts)
  assert_eq(tree.to_string(), expected, msg="tree: " + source)
  let candidate = run_candidate_program(@interpreter.new_interpreter(), stmts)
  assert_eq(candidate.to_string(), expected, msg="candidate: " + source)
}

///|
test "try catch and finally create lexical TDZ before executing statements" {
  for
    declaration in [
      "let value;", "const value = 1;", "let [value] = [1];", "class value {}",
    ] {
    let body = "typeof value; " + declaration
    for
      statement in [
        "try { " + body + " } catch (error) { throw error; }",
        "try { throw 0; } catch (error) { " + body + " }",
        "try {} finally { " + body + " }",
      ] {
      assert_try_block_result(
        "var value = 99; var result = 'no error'; try { " +
        statement +
        " } catch (error) { result = error.name; } result;",
        "ReferenceError",
      )
    }
  }
}

///|
test "try blocks initialize locals and preserve catch parameters and unresolved typeof" {
  let source =
    #|var result = [];
    #|try { let value = 1; result.push(value); throw 2; }
    #|catch (error) { let value = error; result.push(value); }
    #|finally { let value = 3; result.push(value); }
    #|result.push(typeof value);
    #|result.join(',');
  assert_try_block_result(source, "1,2,3,undefined")
}

///|
test "try catch and finally retain lexical TDZ when a generator resumes" {
  for
    body in [
      "try { yield 0; typeof value; let value; } catch (error) { throw error; }",
      "try { throw 0; } catch (error) { yield 0; typeof value; let value; }", "try {} finally { yield 0; typeof value; let value; }",
    ] {
    assert_try_block_result(
      "function* sequence() { " +
      body +
      " } var it = sequence(); it.next();" +
      "var result = 'no error'; try { it.next(); } catch (error) { result = error.name; } result;",
      "ReferenceError",
    )
  }
}
