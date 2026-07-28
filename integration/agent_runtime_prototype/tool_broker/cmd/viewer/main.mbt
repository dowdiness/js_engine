///|
async fn main {
  let viewer = @tool_broker.ToolBrokerViewer()
  @stdio.stdout.write(
    (
      #|PROTOTYPE native ToolBroker state viewer
      #|Walkthrough 1: Worker authority/approval escalation is rejected.
      #|Walkthrough 2: Operator approves, then cancels before host Dispatch.
      #|Each command prints the full before/after state and emitted effects.
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
