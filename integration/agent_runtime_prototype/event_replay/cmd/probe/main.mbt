///|
fn main {
  for line in @event_replay.required_transcript() {
    println(line)
  }
}
