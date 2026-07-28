///|
extern "C" fn sleep_millis(milliseconds : Int) -> Unit = "p2_worker_sleep_millis"

///|
extern "C" fn emit_oversized_output_forever() -> Unit = "p2_worker_emit_oversized_output_forever"

///|
extern "C" fn emit_malformed_then_hang() -> Unit = "p2_worker_emit_malformed_then_hang"

///|
extern "C" fn emit_partial_close_then_hang() -> Unit = "p2_worker_emit_partial_close_then_hang"

///|
extern "C" fn abrupt_exit_process() -> Unit = "p2_worker_abrupt_exit_process"

///|
fn exercise_engine(source : String) -> Unit {
  let engine = @js_engine.Engine()
  match engine.eval_diagnostic(source, source_id="p2-worker-fixture.js") {
    Ok(_) => ()
    Err(diagnostic) =>
      abort(
        "P2 worker fixture Engine failure: " + diagnostic.failure_kind_code(),
      )
  }
}

///|
fn write_completion(scenario : String) -> Unit {
  let message = Json::object({
    "kind": Json::string("completed"),
    "scenario": Json::string(scenario),
    "value": Json::string("js_engine_evaluated"),
  })
  println(message.stringify())
}

///|
fn main {
  let args = @env.args()
  guard args.length() == 2 else { abort("usage: p2-worker <scenario>") }
  match args[1] {
    "normal" => {
      exercise_engine("let p2Value = 1 + 1;")
      write_completion("normal")
    }
    "infinite_js" => exercise_engine("while (true) {}")
    "worker_panic" => {
      exercise_engine("let p2Value = 1 + 1;")
      abort("P2 fixed worker panic")
    }
    "worker_abrupt_exit" => {
      exercise_engine("let p2Value = 1 + 1;")
      abrupt_exit_process()
    }
    "oversized_output" => {
      exercise_engine("let p2BeforeOutput = 1;")
      emit_oversized_output_forever()
    }
    "malformed_json" => {
      exercise_engine("let p2BeforeMalformed = 1;")
      emit_malformed_then_hang()
    }
    "pipe_close_mid_message" => {
      exercise_engine("let p2BeforePartial = 1;")
      emit_partial_close_then_hang()
    }
    "near_deadline" => {
      sleep_millis(800)
      exercise_engine("let p2NearDeadline = 1;")
      write_completion("near_deadline")
    }
    "recovery" => {
      exercise_engine("let p2Recovery = 1;")
      write_completion("recovery")
    }
    scenario => abort("unknown P2 worker scenario: " + scenario)
  }
}
