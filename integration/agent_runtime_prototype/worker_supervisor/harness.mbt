///|
const WORKER_DEADLINE_MS = 1000

///|
const OUTPUT_LIMIT_BYTES = 1_048_576

///|
const KILL_CONFIRMATION_MS = 2000

///|
const POST_REAP_DRAIN_MS = 500

///|
const READ_CHUNK_BYTES = 4096

///|
const POLL_INTERVAL_MS = 5

///|
const WAIT_ERROR = -1

///|
const WAIT_RUNNING = 0

///|
const WAIT_REAPED = 1

///|
const TERMINAL_EXITED = 1

///|
const TERMINAL_SIGNALED = 2

///|
const WORKER_ABRUPT_EXIT_CODE = 86

///|
const SIGABRT = 6

///|
const SIGKILL = 9

///|
const ERRNO_ESRCH = 3

///|
priv enum ChildTerminal {
  Exited(Int)
  Signaled(Int)
}

///|
priv struct AttemptSpec {
  scenario : String
  fixture : String
  expected_classification : String
  is_failure : Bool
  is_recovery : Bool
}

///|
fn AttemptSpec::AttemptSpec(
  scenario : String,
  fixture : String,
  expected_classification : String,
  is_failure? : Bool = false,
  is_recovery? : Bool = false,
) -> AttemptSpec {
  { scenario, fixture, expected_classification, is_failure, is_recovery }
}

///|
priv struct AttemptOutcome {
  pid : Int
}

///|
priv struct ScenarioState {
  supervisor_pid : Int
  run_start : @bench.Timestamp
  emit_line : (String) -> Unit
  scenario : String
  fixture : String
  generation : Int
  worker_pid : Int
  mut phase : String
  mut elapsed_us : Int
  deadline_us : Int
  output_limit_bytes : Int
  mut stdout_bytes : Int
  mut stderr_bytes : Int
  mut total_bytes : Int
  mut stdout_eof : Bool
  mut stderr_eof : Bool
  mut partial_line_bytes : Int
  mut last_valid_message : String?
  mut valid_message_us : Int?
  mut trigger : String?
  mut kill_requested : Bool
  mut kill_request_us : Int?
  mut requested_signal : Int?
  mut kill_errno : Int?
  mut kill_outcome : String?
  mut kill_confirmation_deadline_us : Int?
  mut terminal_kind : String?
  mut exit_code : Int?
  mut observed_signal : Int?
  mut classification : String?
  mut reaped : Bool
  mut reap_us : Int?
  mut active_children : Int
}

///|
fn ScenarioState::ScenarioState(
  supervisor_pid : Int,
  run_start : @bench.Timestamp,
  emit_line : (String) -> Unit,
  scenario : String,
  fixture : String,
  generation : Int,
  worker_pid : Int,
) -> ScenarioState {
  {
    supervisor_pid,
    run_start,
    emit_line,
    scenario,
    fixture,
    generation,
    worker_pid,
    phase: "Running",
    elapsed_us: 0,
    deadline_us: WORKER_DEADLINE_MS * 1000,
    output_limit_bytes: OUTPUT_LIMIT_BYTES,
    stdout_bytes: 0,
    stderr_bytes: 0,
    total_bytes: 0,
    stdout_eof: false,
    stderr_eof: false,
    partial_line_bytes: 0,
    last_valid_message: None,
    valid_message_us: None,
    trigger: None,
    kill_requested: false,
    kill_request_us: None,
    requested_signal: None,
    kill_errno: None,
    kill_outcome: None,
    kill_confirmation_deadline_us: None,
    terminal_kind: None,
    exit_code: None,
    observed_signal: None,
    classification: None,
    reaped: false,
    reap_us: None,
    active_children: 1,
  }
}

///|
/// The sole reaper for the fixed direct child.
#borrow(kind_out, detail_out, errno_out)
extern "C" fn p2_waitpid_nohang(
  pid : Int,
  kind_out : Ref[Int],
  detail_out : Ref[Int],
  errno_out : Ref[Int],
) -> Int = "p2_waitpid_nohang"

///|
/// Sends SIGKILL to the fixed direct child PID; it does not reap.
#borrow(errno_out)
extern "C" fn p2_kill_sigkill(pid : Int, errno_out : Ref[Int]) -> Int = "p2_kill_sigkill"

///|
extern "C" fn supervisor_pid() -> Int = "p2_supervisor_pid"

///|
fn json_int(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn json_optional_int(value : Int?) -> Json {
  match value {
    Some(number) => json_int(number)
    None => Json::null()
  }
}

///|
fn json_optional_string(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn state_json(state : ScenarioState) -> Json {
  Json::object({
    "supervisor_pid": json_int(state.supervisor_pid),
    "phase": Json::string(state.phase),
    "attempt_elapsed_monotonic_us": json_int(state.elapsed_us),
    "run_elapsed_monotonic_us": json_int(monotonic_elapsed_us(state.run_start)),
    "generation": json_int(state.generation),
    "active_children": json_int(state.active_children),
    "worker": Json::object({
      "pid": json_int(state.worker_pid),
      "fixture": Json::string(state.fixture),
      "deadline_us": json_int(state.deadline_us),
    }),
    "io": Json::object({
      "stdout_bytes": json_int(state.stdout_bytes),
      "stderr_bytes": json_int(state.stderr_bytes),
      "total_bytes": json_int(state.total_bytes),
      "limit_bytes": json_int(state.output_limit_bytes),
      "stdout_eof": Json::boolean(state.stdout_eof),
      "stderr_eof": Json::boolean(state.stderr_eof),
      "partial_line_bytes": json_int(state.partial_line_bytes),
      "last_valid_message": json_optional_string(state.last_valid_message),
      "valid_message_us": json_optional_int(state.valid_message_us),
    }),
    "kill": Json::object({
      "trigger": json_optional_string(state.trigger),
      "requested": Json::boolean(state.kill_requested),
      "request_us": json_optional_int(state.kill_request_us),
      "requested_signal": json_optional_int(state.requested_signal),
      "kill_errno": json_optional_int(state.kill_errno),
      "outcome": json_optional_string(state.kill_outcome),
      "confirmation_deadline_us": json_optional_int(
        state.kill_confirmation_deadline_us,
      ),
    }),
    "terminal": Json::object({
      "kind": json_optional_string(state.terminal_kind),
      "exit_code": json_optional_int(state.exit_code),
      "observed_signal": json_optional_int(state.observed_signal),
      "classification": json_optional_string(state.classification),
      "reaped": Json::boolean(state.reaped),
      "reap_us": json_optional_int(state.reap_us),
    }),
  })
}

///|
fn monotonic_elapsed_us(start : @bench.Timestamp) -> Int {
  @bench.monotonic_clock_end(start).to_int()
}

///|
fn record_event(
  transcript : Array[String],
  sequence : Ref[Int],
  state : ScenarioState,
  start : @bench.Timestamp,
  event : String,
) -> Unit {
  state.elapsed_us = monotonic_elapsed_us(start)
  let line = Json::object({
    "schema": Json::string("agent-runtime-p2/v1"),
    "scenario": Json::string(state.scenario),
    "sequence": json_int(sequence.val),
    "event": Json::string(event),
    "state": state_json(state),
  }).stringify()
  transcript.push(line)
  (state.emit_line)(line)
  sequence.val += 1
}

///|
fn set_trigger(
  transcript : Array[String],
  sequence : Ref[Int],
  state : ScenarioState,
  start : @bench.Timestamp,
  trigger : String,
) -> Unit {
  guard state.trigger is None else { return }
  state.trigger = Some(trigger)
  record_event(transcript, sequence, state, start, "terminal_trigger")
  if !state.reaped && state.active_children == 1 {
    request_kill(transcript, sequence, state, start)
  }
}

///|
fn expected_worker_message(fixture : String) -> Json {
  let scenario = if fixture == "recovery" { "recovery" } else { fixture }
  Json::object({
    "kind": Json::string("completed"),
    "scenario": Json::string(scenario),
    "value": Json::string("js_engine_evaluated"),
  })
}

///|
fn accept_protocol_line(
  transcript : Array[String],
  sequence : Ref[Int],
  state : ScenarioState,
  start : @bench.Timestamp,
  bytes : Array[Byte],
) -> Unit {
  let decoded : String? = Some(@utf8.decode(Bytes::from_array(bytes))) catch {
    _ => None
  }
  if state.fixture == "worker_panic" && decoded == Some("P2 fixed worker panic") {
    set_trigger(transcript, sequence, state, start, "worker_panic")
    return
  }
  let parsed : Json? = match decoded {
    Some(text) => Some(@json.parse(text)) catch { _ => None }
    None => None
  }
  match (decoded, parsed, state.last_valid_message) {
    (Some(text), Some(actual), None) =>
      if actual == expected_worker_message(state.fixture) {
        state.last_valid_message = Some(text)
        state.valid_message_us = Some(monotonic_elapsed_us(start))
        record_event(transcript, sequence, state, start, "valid_message")
      } else {
        set_trigger(transcript, sequence, state, start, "malformed_json")
      }
    _ => set_trigger(transcript, sequence, state, start, "malformed_json")
  }
}

///|
fn next_read_size(state : ScenarioState) -> Int {
  guard state.trigger is None else { return READ_CHUNK_BYTES }
  let remaining = state.output_limit_bytes - state.total_bytes
  if remaining >= READ_CHUNK_BYTES {
    READ_CHUNK_BYTES
  } else if remaining >= 0 {
    remaining + 1
  } else {
    READ_CHUNK_BYTES
  }
}

///|
async fn[R : @io.Reader] drain_stdout(
  reader : R,
  transcript : Array[String],
  sequence : Ref[Int],
  state : ScenarioState,
  start : @bench.Timestamp,
) -> Unit {
  let line : Array[Byte] = []
  while reader.read_some(max_len=next_read_size(state)) is Some(chunk) {
    state.stdout_bytes += chunk.length()
    state.total_bytes += chunk.length()
    if state.total_bytes > state.output_limit_bytes {
      set_trigger(transcript, sequence, state, start, "output_limit_exceeded")
    }
    if state.trigger is None {
      for byte in chunk {
        if byte == b'\n' {
          accept_protocol_line(transcript, sequence, state, start, line)
          line.clear()
        } else {
          line.push(byte)
        }
      }
      state.partial_line_bytes = line.length()
    }
    @async.pause()
  }
  state.stdout_eof = true
  if state.trigger is None && !line.is_empty() {
    state.partial_line_bytes = line.length()
    set_trigger(transcript, sequence, state, start, "pipe_closed_mid_message")
  }
}

///|
async fn[R : @io.Reader] drain_stderr(
  reader : R,
  transcript : Array[String],
  sequence : Ref[Int],
  state : ScenarioState,
  start : @bench.Timestamp,
) -> Unit {
  while reader.read_some(max_len=next_read_size(state)) is Some(chunk) {
    state.stderr_bytes += chunk.length()
    state.total_bytes += chunk.length()
    if state.total_bytes > state.output_limit_bytes {
      set_trigger(transcript, sequence, state, start, "output_limit_exceeded")
    }
    @async.pause()
  }
  state.stderr_eof = true
}

///|
fn poll_child(pid : Int) -> ChildTerminal? {
  let kind = Ref(0)
  let detail = Ref(0)
  let errno_out = Ref(0)
  match p2_waitpid_nohang(pid, kind, detail, errno_out) {
    WAIT_RUNNING => None
    WAIT_REAPED =>
      match kind.val {
        TERMINAL_EXITED => Some(Exited(detail.val))
        TERMINAL_SIGNALED => Some(Signaled(detail.val))
        other => abort("unexpected waitpid terminal kind: " + other.to_string())
      }
    WAIT_ERROR =>
      abort("waitpid failed with errno " + errno_out.val.to_string())
    other => abort("unexpected waitpid result: " + other.to_string())
  }
}

///|
fn store_terminal(
  state : ScenarioState,
  terminal : ChildTerminal,
  start : @bench.Timestamp,
) -> Unit {
  state.phase = "Finalizing"
  state.reaped = true
  state.reap_us = Some(monotonic_elapsed_us(start))
  state.active_children = 0
  match terminal {
    Exited(code) => {
      state.terminal_kind = Some("exit")
      state.exit_code = Some(code)
    }
    Signaled(signal) => {
      state.terminal_kind = Some("signal")
      state.observed_signal = Some(signal)
    }
  }
  if state.kill_requested {
    state.kill_outcome = Some(
      match (state.requested_signal, terminal) {
        (Some(requested), Signaled(observed)) if requested == observed =>
          "requested_signal_observed"
        _ => "other_terminal_observed"
      },
    )
  }
}

///|
async fn emergency_cleanup(
  state : ScenarioState,
  start : @bench.Timestamp,
  transcript : Array[String],
  sequence : Ref[Int],
) -> Unit {
  guard !state.reaped else { return }
  if !state.kill_requested {
    let requested_at = monotonic_elapsed_us(start)
    state.phase = "EmergencyKillRequested"
    state.kill_requested = true
    state.kill_request_us = Some(requested_at)
    state.requested_signal = Some(SIGKILL)
    state.kill_confirmation_deadline_us = Some(
      requested_at + KILL_CONFIRMATION_MS * 1000,
    )
    let errno_out = Ref(0)
    if p2_kill_sigkill(state.worker_pid, errno_out) != 0 {
      state.kill_errno = Some(errno_out.val)
    }
  }
  let cleanup_start = @bench.monotonic_clock_start()
  while !state.reaped &&
        monotonic_elapsed_us(cleanup_start) <= KILL_CONFIRMATION_MS * 1000 {
    match poll_child(state.worker_pid) {
      Some(terminal) => store_terminal(state, terminal, start)
      None => @async.sleep(POLL_INTERVAL_MS)
    }
  }
  guard state.reaped else {
    state.phase = "CleanupFailed"
    record_event(
      transcript, sequence, state, start, "emergency_cleanup_timeout",
    )
    abort(
      "emergency cleanup did not reap the worker within the confirmation limit",
    )
  }
  state.phase = "CleanupReady"
  record_event(
    transcript, sequence, state, start, "emergency_cleanup_completed",
  )
}

///|
fn request_kill(
  transcript : Array[String],
  sequence : Ref[Int],
  state : ScenarioState,
  start : @bench.Timestamp,
) -> Unit {
  guard !state.kill_requested && !state.reaped && state.active_children == 1 else {
    return
  }
  let requested_at = monotonic_elapsed_us(start)
  state.phase = "KillRequested"
  state.kill_requested = true
  state.kill_request_us = Some(requested_at)
  state.requested_signal = Some(SIGKILL)
  state.kill_confirmation_deadline_us = Some(
    requested_at + KILL_CONFIRMATION_MS * 1000,
  )
  let errno_out = Ref(0)
  if p2_kill_sigkill(state.worker_pid, errno_out) != 0 {
    state.kill_errno = Some(errno_out.val)
  }
  record_event(transcript, sequence, state, start, "kill_requested")
}

///|
fn classify_terminal(state : ScenarioState, terminal : ChildTerminal) -> String {
  match
    (state.trigger, terminal, state.last_valid_message, state.valid_message_us) {
    (Some("deadline_exceeded"), Exited(0), Some(_), Some(completed)) if completed <
      state.deadline_us =>
      match state.fixture {
        "normal" => "normal_completion"
        "near_deadline" => "near_deadline_completion"
        "recovery" => "recovery_completion"
        _ => "completion"
      }
    (None, Exited(0), Some(_), _) =>
      match state.fixture {
        "normal" => "normal_completion"
        "near_deadline" => "near_deadline_completion"
        "recovery" => "recovery_completion"
        _ => "completion"
      }
    (Some("deadline_exceeded"), _, _, _) => "deadline_exceeded"
    (Some("output_limit_exceeded"), _, _, _) => "output_limit_exceeded"
    (Some("malformed_json"), _, _, _) => "malformed_json"
    (Some("pipe_closed_mid_message"), _, _, _) => "pipe_closed_mid_message"
    (Some("worker_panic"), _, _, _) => "worker_panic"
    (Some(other), _, _, _) => other
    (None, Exited(WORKER_ABRUPT_EXIT_CODE), _, _) if state.fixture ==
      "worker_abrupt_exit" => "abrupt_exit"
    (None, Signaled(SIGABRT), _, _) if state.fixture == "worker_panic" =>
      "worker_panic"
    (None, Signaled(_), _, _) => "unexpected_signal"
    (None, Exited(_), _, _) => "nonzero_exit"
  }
}

///|
fn verify_attempt_state(
  state : ScenarioState,
  terminal : ChildTerminal,
  classification : String,
) -> Unit {
  guard state.reaped && state.active_children == 0 else {
    abort("terminal attempt was not reaped")
  }
  guard state.stdout_eof && state.stderr_eof else {
    abort("terminal attempt did not reach EOF on both pipes")
  }
  if state.kill_requested {
    match terminal {
      Signaled(SIGKILL) => {
        guard state.kill_errno is None else {
          abort("SIGKILL was observed after the kill syscall reported an error")
        }
      }
      Exited(0) if state.last_valid_message is Some(_) =>
        match state.kill_errno {
          None | Some(ERRNO_ESRCH) => ()
          Some(errno) =>
            abort(
              "natural exit followed unexpected kill errno " + errno.to_string(),
            )
        }
      _ =>
        abort(
          "kill request neither observed SIGKILL nor lost to a valid natural exit",
        )
    }
    guard (state.kill_request_us, state.reap_us)
      is (Some(requested), Some(reaped)) else {
      abort("kill/reap timestamps are incomplete")
    }
    guard reaped >= requested &&
      reaped - requested <= KILL_CONFIRMATION_MS * 1000 else {
      abort("kill-to-reap duration exceeded the confirmation limit")
    }
    guard state.kill_outcome is Some(_) else {
      abort("kill request has no recorded terminal race outcome")
    }
  } else {
    match classification {
      "abrupt_exit" => {
        guard terminal is Exited(WORKER_ABRUPT_EXIT_CODE) else {
          abort("abrupt-exit fixture did not terminate with exit 86")
        }
      }
      "worker_panic" => {
        guard terminal is Signaled(SIGABRT) else {
          abort("natural panic fixture did not terminate with SIGABRT")
        }
      }
      _ => {
        guard terminal is Exited(0) else {
          abort("un-killed worker did not exit successfully")
        }
      }
    }
  }
  match classification {
    "normal_completion" | "recovery_completion" | "near_deadline_completion" => {
      guard state.last_valid_message is Some(_) else {
        abort("successful worker has no valid IPC message")
      }
    }
    "output_limit_exceeded" => {
      guard state.total_bytes > state.output_limit_bytes else {
        abort("output-limit classification did not exceed the byte cap")
      }
    }
    "pipe_closed_mid_message" => {
      guard state.partial_line_bytes > 0 && state.stdout_eof else {
        abort("mid-message pipe closure was not observed")
      }
    }
    "worker_panic" | "abrupt_exit" | "malformed_json" | "deadline_exceeded" =>
      ()
    other => abort("unverified attempt classification: " + other)
  }
  if classification == "near_deadline_completion" {
    guard state.valid_message_us is Some(completed) else {
      abort("near-deadline worker has no completion-message timestamp")
    }
    guard completed >= 700_000 && completed < state.deadline_us else {
      abort("near-deadline worker did not complete inside the intended window")
    }
  }
}

///|
async fn run_attempt(
  worker_executable : String,
  spec : AttemptSpec,
  generation : Int,
  supervisor : Int,
  run_start : @bench.Timestamp,
  emit_line : (String) -> Unit,
  transcript : Array[String],
  sequence : Ref[Int],
) -> AttemptOutcome {
  @async.with_task_group() <| group => {
    let start = @bench.monotonic_clock_start()
    let (stdout_reader, stdout_writer) = @process.read_from_process()
    let (stderr_reader, stderr_writer) = @process.read_from_process()
    defer stdout_reader.close()
    defer stderr_reader.close()
    let null_stdin = @process.redirect_from_file("/dev/null")
    let pid = @process.spawn_orphan(
      worker_executable,
      [spec.fixture],
      inherit_env=false,
      stdin=null_stdin,
      stdout=stdout_writer,
      stderr=stderr_writer,
    )
    let state = ScenarioState(
      supervisor,
      run_start,
      emit_line,
      spec.scenario,
      spec.fixture,
      generation,
      pid,
    )
    group.add_defer(() => {
      @async.protect_from_cancel(
        () => emergency_cleanup(state, start, transcript, sequence),
        resume_on_cancel=true,
      )
    })
    record_event(transcript, sequence, state, start, "spawned")
    let stdout_task = group.spawn(() => {
      drain_stdout(stdout_reader, transcript, sequence, state, start)
    })
    let stderr_task = group.spawn(() => {
      drain_stderr(stderr_reader, transcript, sequence, state, start)
    })
    let mut observed : ChildTerminal? = None
    while observed is None {
      match poll_child(pid) {
        Some(terminal) => observed = Some(terminal)
        None => {
          let now = monotonic_elapsed_us(start)
          if state.trigger is None && now >= state.deadline_us {
            set_trigger(transcript, sequence, state, start, "deadline_exceeded")
          }
          if state.trigger is Some(_) && !state.kill_requested {
            request_kill(transcript, sequence, state, start)
          }
          match state.kill_confirmation_deadline_us {
            Some(deadline) if now > deadline => {
              state.phase = "CleanupFailed"
              record_event(
                transcript, sequence, state, start, "kill_confirmation_timeout",
              )
              abort("worker was not reaped within kill confirmation limit")
            }
            _ => ()
          }
          @async.sleep(POLL_INTERVAL_MS)
        }
      }
    }
    guard observed is Some(terminal) else {
      abort("missing terminal observation")
    }
    store_terminal(state, terminal, start)
    record_event(transcript, sequence, state, start, "reaped")
    let drained = @async.with_timeout_opt(POST_REAP_DRAIN_MS, () => {
      stdout_task.wait()
      stderr_task.wait()
    })
    guard drained is Some(_) else {
      state.phase = "CleanupFailed"
      record_event(
        transcript, sequence, state, start, "post_reap_drain_timeout",
      )
      abort("stdout/stderr drain did not finish after reap")
    }
    let classification = classify_terminal(state, terminal)
    verify_attempt_state(state, terminal, classification)
    state.classification = Some(classification)
    state.phase = "Ready"
    record_event(transcript, sequence, state, start, "attempt_completed")
    guard classification == spec.expected_classification else {
      abort(
        "scenario " +
        spec.scenario +
        " classified as " +
        classification +
        ", expected " +
        spec.expected_classification,
      )
    }
    { pid, }
  }
}

///|
fn required_attempts() -> Array[AttemptSpec] {
  [
    AttemptSpec("normal", "normal", "normal_completion"),
    AttemptSpec(
      "infinite_js",
      "infinite_js",
      "deadline_exceeded",
      is_failure=true,
    ),
    AttemptSpec(
      "recovery_after_infinite_js",
      "recovery",
      "recovery_completion",
      is_recovery=true,
    ),
    AttemptSpec("worker_panic", "worker_panic", "worker_panic", is_failure=true),
    AttemptSpec(
      "recovery_after_worker_panic",
      "recovery",
      "recovery_completion",
      is_recovery=true,
    ),
    AttemptSpec(
      "worker_abrupt_exit",
      "worker_abrupt_exit",
      "abrupt_exit",
      is_failure=true,
    ),
    AttemptSpec(
      "recovery_after_worker_abrupt_exit",
      "recovery",
      "recovery_completion",
      is_recovery=true,
    ),
    AttemptSpec(
      "oversized_output",
      "oversized_output",
      "output_limit_exceeded",
      is_failure=true,
    ),
    AttemptSpec(
      "recovery_after_oversized_output",
      "recovery",
      "recovery_completion",
      is_recovery=true,
    ),
    AttemptSpec(
      "malformed_json",
      "malformed_json",
      "malformed_json",
      is_failure=true,
    ),
    AttemptSpec(
      "recovery_after_malformed_json",
      "recovery",
      "recovery_completion",
      is_recovery=true,
    ),
    AttemptSpec(
      "pipe_close_mid_message",
      "pipe_close_mid_message",
      "pipe_closed_mid_message",
      is_failure=true,
    ),
    AttemptSpec(
      "recovery_after_pipe_close",
      "recovery",
      "recovery_completion",
      is_recovery=true,
    ),
    AttemptSpec("near_deadline", "near_deadline", "near_deadline_completion"),
  ]
}

///|
/// Executes the complete P2 matrix in one supervisor process.
pub async fn required_matrix_transcript(
  worker_executable : String,
  emit_line? : (String) -> Unit = _ => (),
) -> Array[String] {
  guard worker_executable.has_prefix("/") else {
    abort("worker executable must be an absolute path")
  }
  let transcript : Array[String] = []
  let sequence = Ref(0)
  let supervisor = supervisor_pid()
  let run_start = @bench.monotonic_clock_start()
  let mut generation = 0
  let mut failures = 0
  let mut recoveries = 0
  let mut last_failure_pid : Int? = None
  for spec in required_attempts() {
    generation += 1
    let outcome = run_attempt(
      worker_executable, spec, generation, supervisor, run_start, emit_line, transcript,
      sequence,
    )
    if spec.is_failure {
      failures += 1
      last_failure_pid = Some(outcome.pid)
    }
    if spec.is_recovery {
      guard last_failure_pid is Some(failure_pid) else {
        abort("recovery attempt has no preceding failure")
      }
      guard outcome.pid != failure_pid else {
        abort("recovery worker did not receive a fresh PID")
      }
      recoveries += 1
      last_failure_pid = None
    }
  }
  guard generation == 14 && failures == 6 && recoveries == 6 else {
    abort("P2 matrix cardinality invariant failed")
  }
  let summary = Json::object({
    "schema": Json::string("agent-runtime-p2-summary/v1"),
    "kind": Json::string("matrix_summary"),
    "sequence": json_int(sequence.val),
    "supervisor_pid": json_int(supervisor),
    "run_elapsed_monotonic_us": json_int(monotonic_elapsed_us(run_start)),
    "attempts": json_int(generation),
    "failure_classes": json_int(failures),
    "fresh_recoveries": json_int(recoveries),
    "active_children": json_int(0),
    "verdict": Json::string("GO"),
    "killability_scope": Json::string("native Linux/WSL fixed direct child"),
    "security_scope": Json::string("no sandbox or hostile-code claim"),
  }).stringify()
  transcript.push(summary)
  emit_line(summary)
  transcript
}
