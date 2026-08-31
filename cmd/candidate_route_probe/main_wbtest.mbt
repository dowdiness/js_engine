///|
test "route probe reports a source without executing it" {
  let report = route_probe_report("var value = 1; value += 2;")
  json_inspect(report, content={
    "schema_version": 1,
    "summary": {
      "functions": 1,
      "bytecode": 0,
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
    ],
  })
}

///|
test "route probe error message is stable" {
  inspect(
    route_probe_error_message("broken input"),
    content="Error: broken input",
  )
}
