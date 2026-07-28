///|
fn main {
  let transcript = @tool_broker.required_transcript()
  guard transcript.length() > 0 else {
    abort("required ToolBroker transcript is empty")
  }
  for line in transcript {
    println(line)
  }
}
