///|
test "playground_run returns a completed wire response" {
  let response = @bridge.playground_run(
    "console.log(1 + 2); 6 * 7;", "playground:test",
  )
  let json = @json.parse(response)
  let fields : Map[String, Json] = @json.from_json(json)
  json_inspect(fields["protocolVersion"], content=1)
  json_inspect(fields["kind"], content="completed")
  json_inspect(fields["output"], content=["3"])
  json_inspect(fields["result"], content="42")
}

///|
test "playground_run returns source diagnostics" {
  let response = @bridge.playground_run("let =", "playground:parse")
  let json = @json.parse(response)
  let fields : Map[String, Json] = @json.from_json(json)
  json_inspect(fields["protocolVersion"], content=1)
  json_inspect(fields["kind"], content="failed")
  json_inspect(fields["output"], content=[])
  json_inspect(fields["partialOutputAvailable"], content=false)
  let diagnostic : Map[String, Json] = @json.from_json(fields["diagnostic"])
  json_inspect(diagnostic["failureKind"], content="parse-error")
  json_inspect(diagnostic["phase"], content="parse")
  json_inspect(diagnostic["sourceId"], content="playground:parse")
  let location : Map[String, Json] = @json.from_json(diagnostic["location"])
  let start : Map[String, Json] = @json.from_json(location["start"])
  json_inspect(start["line"], content=1)
  json_inspect(start["column"], content=5)
}
