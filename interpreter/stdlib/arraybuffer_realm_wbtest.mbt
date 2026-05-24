///| Whitebox tests for stdlib ArrayBuffer backing-store ownership by RealmState.

///|
test "ArrayBuffer backing store and detached state are realm-isolated" {
  let realm_a = @runtime.RealmState()
  let realm_b = @runtime.RealmState()
  let buffer_a = make_arraybuffer_object(realm_a, 4, Value::Null)
  let buffer_b = make_arraybuffer_object(realm_b, 4, Value::Null)
  let id_a = match get_buffer_id(buffer_a) {
    Some(id) => id
    None => fail("realm A ArrayBuffer id missing")
  }
  let id_b = match get_buffer_id(buffer_b) {
    Some(id) => id
    None => fail("realm B ArrayBuffer id missing")
  }

  // This pins the target RealmState behavior: each realm owns its own
  // ArrayBuffer id counter, so the first buffer in two fresh realms can use
  // the same numeric id without sharing backing bytes or detached state.
  assert_eq(id_a, 0)
  assert_eq(id_b, 0)

  match get_arraybuffer_bytes(realm_a, id_a) {
    Some(bytes) => bytes[0] = 42
    None => fail("realm A ArrayBuffer bytes missing")
  }
  match get_arraybuffer_bytes(realm_b, id_b) {
    Some(bytes) => assert_eq(bytes[0], 0)
    None => fail("realm B ArrayBuffer bytes missing")
  }

  detach_arraybuffer(realm_a, id_a)
  assert_true(is_arraybuffer_detached(realm_a, id_a))
  assert_false(is_arraybuffer_detached(realm_b, id_b))
}
