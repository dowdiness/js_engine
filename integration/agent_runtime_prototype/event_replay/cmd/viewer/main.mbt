///|
async fn main {
  let viewer = @event_replay.EventReplayViewer()
  @stdio.stdout.write(
    (
      #|PROTOTYPE native event-log replay viewer
      #|Controls expose start, approval, result return, Engine crash, replay,
      #|cancellation, and explicit same-key unknown-outcome reconciliation.
      #|Each command prints the complete event log and replay/broker/adapter state.
      #|Type quit or send EOF to exit.
      #|
    ),
  )
  @stdio.stdout.write(
    "initial state\n" + viewer.state().stringify(indent=2) + "\n",
  )
  while true {
    @stdio.stdout.write("command [" + viewer.prompt() + "]> ")
    match @stdio.stdin.read_until("\n") {
      None => {
        @stdio.stdout.write("EOF\n")
        return
      }
      Some(line) => {
        let command = line.trim().to_owned()
        if command == "quit" {
          @stdio.stdout.write("exit\n")
          return
        }
        @stdio.stdout.write(viewer.apply(command).stringify(indent=2) + "\n")
      }
    }
  }
}
