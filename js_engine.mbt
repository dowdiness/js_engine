///|
pub fn run(source : String) -> (Array[String], String) raise Error {
  let interp = @interpreter.Interpreter::new()
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  (interp.output, result.to_string())
}
