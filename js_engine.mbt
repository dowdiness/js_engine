///|
pub fn run(source : String) -> (Array[String], String) raise Error {
  let interp = @interpreter.Interpreter::new()
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  // Drain microtask queue after script execution
  // This implements the event loop checkpoint per WHATWG spec
  interp.run_microtasks()
  (interp.output, result.to_string())
}

///|
/// Run JavaScript source with event loop support
/// This version allows the host to control microtask execution timing
pub fn run_with_event_loop(source : String) -> (@interpreter.Interpreter, @interpreter.Value) raise Error {
  let interp = @interpreter.Interpreter::new()
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  // Return interpreter to allow host to manage event loop
  (interp, result)
}

///|
/// Check if there are pending microtasks in the queue
pub fn has_pending_microtasks(interp : @interpreter.Interpreter) -> Bool {
  interp.microtask_queue.length() > 0
}

///|
/// Run a single microtask checkpoint
/// Returns true if there are more microtasks to process
pub fn run_microtask_checkpoint(interp : @interpreter.Interpreter) -> Bool raise Error {
  interp.run_microtasks()
  interp.microtask_queue.length() > 0
}
