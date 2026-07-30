///|
priv suberror ActivationObservationProbeError {
  ActivationObservationProbeError(String)
}

///|
fn activation_observation_probe_port(
  events : Array[String],
  allow_entry : Bool,
) -> ActivationObservationPort {
  ActivationObservationPort(
    begin_entry=() => {
      events.push("attempt")
      guard allow_entry else {
        raise ActivationObservationProbeError("entry rejected")
      }
      ActivationObservationAttemptHooks(
        accepted=() => events.push("accepted"),
        rejected=() => events.push("rejected"),
        released=() => events.push("released"),
      )
    },
    denied=() => events.push("rejected"),
  )
}

///|
fn expect_invalid_activation_observation(
  action : () -> Unit raise InvalidActivationObservationTransition,
) -> Unit raise {
  let invalid = try {
    action()
    false
  } catch {
    InvalidActivationObservationTransition(_) => true
  }
  inspect(invalid, content="true")
}

///|
test "activation observation accepts then releases exactly once" {
  let events : Array[String] = []
  let attempt = observe_activation_entry(
    activation_observation_probe_port(events, true),
  )
  json_inspect(events, content=["attempt"])
  let token = attempt.accept()
  json_inspect(events, content=["attempt", "accepted"])
  token.release()
  json_inspect(events, content=["attempt", "accepted", "released"])
  expect_invalid_activation_observation(() => token.release())
  expect_invalid_activation_observation(() => {
    let _ = attempt.accept()
  })
  expect_invalid_activation_observation(() => attempt.reject())
  json_inspect(events, content=["attempt", "accepted", "released"])
}

///|
test "activation observation rejects an unacquired entry without release" {
  let events : Array[String] = []
  let attempt = observe_activation_entry(
    activation_observation_probe_port(events, true),
  )
  attempt.reject()
  json_inspect(events, content=["attempt", "rejected"])
  expect_invalid_activation_observation(() => attempt.reject())
  expect_invalid_activation_observation(() => {
    let _ = attempt.accept()
  })
  json_inspect(events, content=["attempt", "rejected"])
}

///|
test "activation observation reports a denied attempt without issuing a token" {
  let events : Array[String] = []
  let observed : Result[ActivationEntryAttempt, Error] = Ok(
    observe_activation_entry(activation_observation_probe_port(events, false)),
  ) catch {
    error => Err(error)
  }
  match observed {
    Err(ActivationObservationProbeError(message)) =>
      inspect(message, content="entry rejected")
    _ => fail("expected the observation port to reject entry")
  }
  json_inspect(events, content=["attempt", "rejected"])
}

///|
test "allow-all activation observation preserves one-shot ownership" {
  let attempt = observe_activation_entry(
    allow_all_activation_observation_port(),
  )
  let token = attempt.accept()
  token.release()
  expect_invalid_activation_observation(() => token.release())
}
