///|
/// PROTOTYPE thin shell around only the stable Engine/eval/call_json facade.
priv struct EngineShell {
  mut engine_ : @js_engine.Engine?
  epoch_ : Int
}

///|
fn EngineShell::EngineShell(
  epoch : Int,
) -> EngineShell raise @js_engine.EngineError {
  let engine = @js_engine.Engine()
  engine.eval(AGENT_SOURCE)
  { engine_: Some(engine), epoch_: epoch }
}

///|
fn EngineShell::call(
  self : EngineShell,
  name : String,
  args : Array[Json],
) -> Json raise @js_engine.EngineError {
  match self.engine_ {
    Some(engine) => engine.call_json(name, args)
    None => abort("PROTOTYPE invariant: crashed Engine cannot be called")
  }
}

///|
fn EngineShell::start(
  self : EngineShell,
  input : Json,
) -> Json raise @js_engine.EngineError {
  self.call("start_agent_session", [input])
}

///|
fn EngineShell::supply_result(
  self : EngineShell,
  result : Json,
) -> Json raise @js_engine.EngineError {
  self.call("resume_agent_session", [result])
}

///|
fn EngineShell::crash(self : EngineShell) -> Unit {
  self.engine_ = None
}

///|
fn EngineShell::epoch(self : EngineShell) -> Int {
  self.epoch_
}

///|
fn EngineShell::status(self : EngineShell) -> String {
  match self.engine_ {
    Some(_) => "live"
    None => "crashed"
  }
}
