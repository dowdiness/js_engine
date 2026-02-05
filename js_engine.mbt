///|
pub fn fib(n : Int) -> Int64 {
  loop (n, 0L, 1L) {
    (0, _, b) => b
    (i, a, b) => continue (i - 1, b, a + b)
  }
}

///|
/// data is a labelled argument without default value having type Array[Int]
/// start is an optional labelled argument with default value 0 having type Int
/// length is an optional labelled argument without default value having type Option[Int]
pub fn sum(data~ : Array[Int], start? : Int = 0, length? : Int) -> Int {
  let end = if length is Some(length) { start + length } else { data.length() }
  for i = start, sum = 0; i < end; i = i + 1, sum = sum + data[i] {

  } else {
    sum
  }
}

///|
pub fn run(source : String) -> (Array[String], String) raise Error {
  let interp = @interpreter.Interpreter::new()
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  // Drain microtask queue after script execution
  // This implements the event loop checkpoint per WHATWG spec
  interp.run_microtasks()
  // Process timer task queue with microtask checkpoints between each
  interp.run_timers()
  (interp.output, result.to_string())
}

///|
/// Run JavaScript source with event loop support
/// This version allows the host to control microtask and timer execution timing
pub fn run_with_event_loop(
  source : String,
) -> (@interpreter.Interpreter, @interpreter.Value) raise Error {
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
/// Check if there are pending timers in the queue
pub fn has_pending_timers(interp : @interpreter.Interpreter) -> Bool {
  interp.timer_queue.length() > 0
}

///|
/// Run a single microtask checkpoint
/// Returns true if there are more microtasks to process
pub fn run_microtask_checkpoint(
  interp : @interpreter.Interpreter,
) -> Bool raise Error {
  interp.run_microtasks()
  interp.microtask_queue.length() > 0
}

///|
/// Run all pending timers with microtask draining between each
pub fn run_timer_checkpoint(
  interp : @interpreter.Interpreter,
) -> Unit raise Error {
  interp.run_timers()
}
