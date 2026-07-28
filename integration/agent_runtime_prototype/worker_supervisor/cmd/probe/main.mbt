///|
extern "C" fn flush_stdout() -> Unit = "p2_probe_flush_stdout"

///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    abort("usage: supervisor-probe <worker-executable>")
  }
  let transcript = @worker_supervisor.required_matrix_transcript(args[1], emit_line=line => {
    println(line)
    flush_stdout()
  })
  guard transcript.length() > 0 else {
    abort("required supervisor transcript is empty")
  }
}
