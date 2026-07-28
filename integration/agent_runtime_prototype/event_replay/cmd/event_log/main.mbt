///|
fn main {
  for line in @event_replay.required_event_log() {
    println(line)
  }
}
