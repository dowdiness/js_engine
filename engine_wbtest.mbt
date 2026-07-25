///|
test "Engine diagnostic classifies timer queue dispatch failures" {
  let diagnostic = timer_dispatch_diagnostic(
    Failure::Failure("invalid timer queue policy transition"),
  )
  inspect(diagnostic.failure_kind_code(), content="internal-error")
  inspect(diagnostic.operation_code(), content="timer-checkpoint")
  inspect(diagnostic.phase_code(), content="timer-dispatch")
  inspect(diagnostic.source_identity() is None, content="true")
  inspect(
    diagnostic.engine_integrity() is EngineIntegrity::Discard,
    content="true",
  )
  inspect(
    diagnostic.retained_effects() is RetainedEffects::Unknown,
    content="true",
  )
  inspect(diagnostic.pending_jobs() is PendingJobs::Unknown, content="true")
}
