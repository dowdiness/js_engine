///|
const SKETCH_READINESS_HARNESS =
  #|function __diagoReadinessRectangle(width, height, strokeWidth) {
  #|  const node = rc.rectangle(0, 0, width, height, {
  #|    fill: "#000",
  #|    stroke: "#000",
  #|    strokeWidth,
  #|    fillWeight: 2,
  #|    hachureGap: 16,
  #|    fillStyle: "solid",
  #|    bowing: 2,
  #|    seed: 1,
  #|  });
  #|  const children = node.children || [];
  #|  return {
  #|    multiple_paths: children.length >= 2,
  #|    all_paths_nonempty: children.every((child) =>
  #|      typeof child.attrs?.d === "string" && child.attrs.d.length > 0
  #|    ),
  #|  };
  #|}

///|
fn load_roughjs() -> @js_engine.Engine raise @js_engine.EngineError {
  let engine = @js_engine.Engine()
  run_diago_source(engine, sketch_runtime_source)
  run_diago_source(engine, sketch_setup_source)
  run_diago_source(engine, SKETCH_READINESS_HARNESS)
  engine
}

///|
test "diago readiness: Rough.js rectangle produces multiple paths" {
  let engine = load_roughjs()
  let result = engine.call_json("__diagoReadinessRectangle", [
    Json::number(100.0),
    Json::number(60.0),
    Json::number(2.0),
  ])
  ignore(engine.run_microtask_checkpoint())
  engine.run_timer_checkpoint()
  json_inspect(result, content={
    "multiple_paths": true,
    "all_paths_nonempty": true,
  })
}
