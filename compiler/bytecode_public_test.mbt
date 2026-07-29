///|
test "bytecode public compatibility adapter remains callable" {
  let program = compile_script_to_bytecode(@parser.parse("1 + 2;").stmts)
  let value = program.run(@interpreter.new_interpreter())
  inspect(value.to_string(), content="3")
}
