///|
test "rule engine preserves state and isolates engines" {
  json_inspect(evaluate_demo(), content=[
    { "allowed": true, "evaluationCount": 1 },
    { "allowed": false, "evaluationCount": 2 },
    { "allowed": true, "evaluationCount": 3 },
    { "allowed": true, "evaluationCount": 1 },
  ])
}
