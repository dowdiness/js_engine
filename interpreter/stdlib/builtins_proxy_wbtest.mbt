///|
test "Proxy builtin setup installs the realm canonical constructor identity" {
  let env = @runtime.Environment::new()
  let realm_state = @runtime.RealmState()
  env.realm_state = Some(realm_state)
  setup_proxy_builtins(env, realm_state)
  let installed = env.get("Proxy")
  let canonical = @runtime.make_canonical_proxy_constructor(realm_state)
  guard installed is Object(installed_data) &&
    canonical is Object(canonical_data) else {
    fail("expected Proxy constructor objects")
  }
  inspect(physical_equal(installed_data, canonical_data), content="true")
}
