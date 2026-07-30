///|
fn alternate_proxy_constructor_for_identity_test(
  _interp : Interpreter,
  args : Array[Value],
) -> Value raise Error {
  guard args.length() == 2 else {
    raise @errors.TypeError(message="expected Proxy target and handler")
  }
  Proxy({
    target: Some(args[0]),
    handler: Some(args[1]),
    is_callable: is_callable(args[0]),
    is_constructor: is_constructor_value(args[0]),
  })
}

///|
test "canonical Proxy constructor identity rejects a same-name alternate" {
  let realm_state = RealmState()
  let alternate : Value = Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: Some(
      ConstructorOnlyCallable(
        "Proxy", alternate_proxy_constructor_for_identity_test,
      ),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  inspect(
    realm_state.canonical_proxy_constructor_matches(alternate),
    content="false",
  )
  let canonical = make_canonical_proxy_constructor(realm_state)
  inspect(
    realm_state.canonical_proxy_constructor_matches(canonical),
    content="true",
  )
  inspect(
    realm_state.canonical_proxy_constructor_matches(alternate),
    content="false",
  )
  let repeated = make_canonical_proxy_constructor(realm_state)
  inspect(
    realm_state.canonical_proxy_constructor_matches(repeated),
    content="true",
  )
  let other_realm = RealmState()
  let other_canonical = make_canonical_proxy_constructor(other_realm)
  inspect(
    realm_state.canonical_proxy_constructor_matches(other_canonical),
    content="false",
  )
  inspect(
    other_realm.canonical_proxy_constructor_matches(canonical),
    content="false",
  )
}
