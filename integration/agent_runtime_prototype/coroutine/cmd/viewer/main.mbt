///|
async fn main {
  let viewer = @coroutine.InactiveUserViewer()
  @stdio.stdout.write(
    (
      #|PROTOTYPE native state viewer: inactive_user_success
      #|Commands advance one deterministic action at a time.
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
