///|
fn arg_to_number_or(
  interp : Interpreter,
  args : Array[Value],
  index : Int32,
  fallback : Double,
) -> Double raise Error {
  if args.length() > index {
    interp.to_number(args[index])
  } else {
    fallback
  }
}
