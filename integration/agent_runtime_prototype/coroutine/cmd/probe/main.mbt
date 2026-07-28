///|
fn main {
  let transcript = @coroutine.required_transcript()
  guard transcript.length() > 0 else {
    abort("required scenario transcript is empty")
  }
  for line in transcript {
    println(line)
  }
}
