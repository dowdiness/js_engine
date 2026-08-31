///|
test "candidate route plan diagnostic separates selected executors and reasons" {
  let source =
    #|function compiled(value) { return value + 1; }
    #|var count = 0;
    #|count += 1;
  let report = profile_candidate_route_plan_json(@parser.parse(source).stmts)
  json_inspect(report, content={
    "schema_version": 1,
    "summary": {
      "functions": 2,
      "bytecode": 1,
      "tree": 1,
      "lowering_unsupported": 0,
      "activation_unsupported": 1,
    },
    "functions": [
      {
        "path": [],
        "name": null,
        "executor": "tree",
        "reason_phase": "activation",
        "reason": "binary operation",
      },
      {
        "path": [0],
        "name": "compiled",
        "executor": "bytecode",
        "reason_phase": null,
        "reason": null,
      },
    ],
  })
}

///|
test "candidate route profile reports lowering fallback separately" {
  let report = profile_candidate_route_plan_json(
    @parser.parse("class Value {}").stmts,
  )
  json_inspect(report, content={
    "schema_version": 1,
    "summary": {
      "functions": 1,
      "bytecode": 0,
      "tree": 1,
      "lowering_unsupported": 1,
      "activation_unsupported": 0,
    },
    "functions": [
      {
        "path": [],
        "name": null,
        "executor": "tree",
        "reason_phase": "lowering",
        "reason": "class declaration",
      },
    ],
  })
}
