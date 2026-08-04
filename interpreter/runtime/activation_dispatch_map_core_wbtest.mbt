///|
fn map_test_state(length : Int64) -> MapState {
  MapState(
    length~,
    receiver=Undefined,
    result=make_array([]),
    callback=Undefined,
    this_arg=Undefined,
    pending_result_consumer=DispatchCompleteReturn,
  )
}

///|
test "array map reducer advances absent elements without Get" {
  let (awaiting, decision) = reduce_array_map(map_test_state(1L), MapStart)
  match decision {
    MapRequestHasProperty(0L) => ()
    _ => fail("map start must request HasProperty")
  }
  let (completed, decision) = reduce_array_map(awaiting, MapHasProperty(false))
  match decision {
    MapComplete(_, DispatchCompleteReturn) => ()
    _ => fail("absent element must complete without Get")
  }
  guard completed.phase is MapCompleted else {
    fail("absent element completion must be terminal")
  }
}

///|
test "array map reducer acknowledges callback and property definition" {
  let state = map_test_state(1L)
  let (after_start, _) = reduce_array_map(state, MapStart)
  let (after_has, _) = reduce_array_map(after_start, MapHasProperty(true))
  let (after_get, decision) = reduce_array_map(
    after_has,
    MapGotValue(Number(2.0)),
  )
  match decision {
    MapRequestCallback(_, _, 0L, _, Number(2.0)) => ()
    _ => fail("present element must request callback with spec arguments")
  }
  let (after_callback, decision) = reduce_array_map(
    after_get,
    MapCallbackReturned(Number(3.0)),
  )
  match decision {
    MapRequestDefine(0L, Number(3.0)) => ()
    _ => fail("callback result must request property definition")
  }
  let (completed, decision) = reduce_array_map(
    after_callback,
    MapPropertyDefined,
  )
  match decision {
    MapComplete(_, DispatchCompleteReturn) => ()
    _ => fail("property acknowledgement must complete the one-element map")
  }
  guard completed.phase is MapCompleted else {
    fail("normal map completion must be terminal")
  }
}

///|
test "array map reducer resumes index one before completion for length two" {
  let state = map_test_state(2L)
  let (after_start, _) = reduce_array_map(state, MapStart)
  let (after_first_has, _) = reduce_array_map(after_start, MapHasProperty(true))
  let (after_first_get, first_callback) = reduce_array_map(
    after_first_has,
    MapGotValue(Number(2.0)),
  )
  match first_callback {
    MapRequestCallback(_, _, 0L, _, Number(2.0)) => ()
    _ => fail("length-two map must request callback at index zero first")
  }
  let (after_first_callback, first_define) = reduce_array_map(
    after_first_get,
    MapCallbackReturned(Number(3.0)),
  )
  match first_define {
    MapRequestDefine(0L, Number(3.0)) => ()
    _ => fail("index-zero callback must define the first result")
  }
  let (after_first_define, second_has) = reduce_array_map(
    after_first_callback,
    MapPropertyDefined,
  )
  match second_has {
    MapRequestHasProperty(1L) => ()
    _ => fail("length-two map must request HasProperty for index one")
  }
  let (after_second_has, _) = reduce_array_map(
    after_first_define,
    MapHasProperty(true),
  )
  let (after_second_get, second_callback) = reduce_array_map(
    after_second_has,
    MapGotValue(Number(4.0)),
  )
  match second_callback {
    MapRequestCallback(_, _, 1L, _, Number(4.0)) => ()
    _ => fail("length-two map must request callback at index one")
  }
  let (after_second_callback, second_define) = reduce_array_map(
    after_second_get,
    MapCallbackReturned(Number(5.0)),
  )
  match second_define {
    MapRequestDefine(1L, Number(5.0)) => ()
    _ => fail("index-one callback must define the second result")
  }
  let (completed, completion) = reduce_array_map(
    after_second_callback,
    MapPropertyDefined,
  )
  match completion {
    MapComplete(_, DispatchCompleteReturn) => ()
    _ => fail("length-two map must complete only after index one definition")
  }
  guard completed.phase is MapCompleted else {
    fail("length-two map completion must be terminal")
  }
}

///|
test "array map reducer rejects invalid order and double consumption" {
  let state = map_test_state(1L)
  let invalid : Result[(MapState, MapDecision), InvalidMapTransition] = Ok(
    reduce_array_map(state, MapGotValue(Undefined)),
  ) catch {
    error => Err(error)
  }
  guard invalid is Err(_) else {
    fail("Get result before HasProperty must reject")
  }
  let (awaiting, _) = reduce_array_map(state, MapStart)
  let (completed, _) = reduce_array_map(awaiting, MapHasProperty(false))
  let double : Result[(MapState, MapDecision), InvalidMapTransition] = Ok(
    reduce_array_map(completed, MapPropertyDefined),
  ) catch {
    error => Err(error)
  }
  guard double is Err(_) else { fail("terminal map state must reject reuse") }
}

///|
test "array map reducer preserves abrupt guest identity and terminal cleanup" {
  let state = map_test_state(1L)
  let (awaiting, _) = reduce_array_map(state, MapStart)
  let marker = make_array([String_("member marker")])
  let guest_throw : Error = JsException(marker)
  let (aborted, decision) = reduce_array_map(awaiting, MapAbrupt(guest_throw))
  match decision {
    MapAbort(JsException(actual)) =>
      match (marker, actual) {
        (Array(expected_data), Array(actual_data)) =>
          if !physical_equal(expected_data, actual_data) {
            fail("map abort changed the guest throw identity")
          }
        _ => fail("map abort lost the guest throw value")
      }
    _ => fail("abrupt map event must produce MapAbort")
  }
  guard aborted.phase is MapFailed else {
    fail("abrupt map event must leave a terminal failed state")
  }
  let reuse : Result[(MapState, MapDecision), InvalidMapTransition] = Ok(
    reduce_array_map(aborted, MapStart),
  ) catch {
    error => Err(error)
  }
  guard reuse is Err(_) else {
    fail("failed map state must reject terminal reuse")
  }
}

///|
test "array map reducer preserves abrupt identity at both length-two indices" {
  let first_state = map_test_state(2L)
  let (first_started, _) = reduce_array_map(first_state, MapStart)
  let (first_has, _) = reduce_array_map(first_started, MapHasProperty(true))
  let (first_callback, _) = reduce_array_map(
    first_has,
    MapGotValue(Number(2.0)),
  )
  let first_marker = make_array([String_("index zero marker")])
  let (first_failed, first_decision) = reduce_array_map(
    first_callback,
    MapAbrupt(JsException(first_marker)),
  )
  match first_decision {
    MapAbort(JsException(actual)) =>
      match (first_marker, actual) {
        (Array(expected_data), Array(actual_data)) =>
          if !physical_equal(expected_data, actual_data) {
            fail("index-zero abrupt identity changed")
          }
        _ => fail("index-zero abrupt value changed type")
      }
    _ => fail("index-zero abrupt event was not terminal")
  }
  guard first_failed.phase is MapFailed else {
    fail("index-zero abrupt state was not terminal")
  }

  let between_state = map_test_state(2L)
  let (between_started, _) = reduce_array_map(between_state, MapStart)
  let (between_has, _) = reduce_array_map(between_started, MapHasProperty(true))
  let (between_get, _) = reduce_array_map(between_has, MapGotValue(Number(2.0)))
  let (between_callback, _) = reduce_array_map(
    between_get,
    MapCallbackReturned(Number(3.0)),
  )
  let (between_second, _) = reduce_array_map(
    between_callback,
    MapPropertyDefined,
  )
  let between_marker = make_array([String_("between marker")])
  let (between_failed, between_decision) = reduce_array_map(
    between_second,
    MapAbrupt(JsException(between_marker)),
  )
  match between_decision {
    MapAbort(JsException(actual)) =>
      match (between_marker, actual) {
        (Array(expected_data), Array(actual_data)) =>
          if !physical_equal(expected_data, actual_data) {
            fail("between-indices abrupt identity changed")
          }
        _ => fail("between-indices abrupt value changed type")
      }
    _ => fail("between-indices abrupt event was not terminal")
  }
  guard between_failed.phase is MapFailed else {
    fail("between-indices abrupt state was not terminal")
  }

  let second_state = map_test_state(2L)
  let (second_started, _) = reduce_array_map(second_state, MapStart)
  let (second_has, _) = reduce_array_map(second_started, MapHasProperty(true))
  let (second_get, _) = reduce_array_map(second_has, MapGotValue(Number(2.0)))
  let (second_callback, _) = reduce_array_map(
    second_get,
    MapCallbackReturned(Number(3.0)),
  )
  let (second_defined, _) = reduce_array_map(
    second_callback,
    MapPropertyDefined,
  )
  let (second_has_ack, _) = reduce_array_map(
    second_defined,
    MapHasProperty(true),
  )
  let (second_get_ack, _) = reduce_array_map(
    second_has_ack,
    MapGotValue(Number(4.0)),
  )
  let second_marker = make_array([String_("index one marker")])
  let (second_failed, second_decision) = reduce_array_map(
    second_get_ack,
    MapAbrupt(JsException(second_marker)),
  )
  match second_decision {
    MapAbort(JsException(actual)) =>
      match (second_marker, actual) {
        (Array(expected_data), Array(actual_data)) =>
          if !physical_equal(expected_data, actual_data) {
            fail("index-one abrupt identity changed")
          }
        _ => fail("index-one abrupt value changed type")
      }
    _ => fail("index-one abrupt event was not terminal")
  }
  guard second_failed.phase is MapFailed else {
    fail("index-one abrupt state was not terminal")
  }
}
