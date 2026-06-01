///|
priv struct BuiltinSetupProfiler {
  timings : Array[(String, Double)]
  mut last_ms : Double
}

///|
fn BuiltinSetupProfiler::BuiltinSetupProfiler() -> BuiltinSetupProfiler {
  { timings: [], last_ms: builtin_setup_profile_now_ms() }
}

///|
fn BuiltinSetupProfiler::mark(
  self : BuiltinSetupProfiler,
  name : String,
) -> Unit {
  let now = builtin_setup_profile_now_ms()
  self.timings.push((name, now - self.last_ms))
  self.last_ms = now
}

///|
fn mark_builtin_setup_phase(
  profile : BuiltinSetupProfiler?,
  name : String,
) -> Unit {
  match profile {
    Some(profile) => profile.mark(name)
    None => ()
  }
}

///|
/// Benchmark-only helper for startup profiling. This is public so the
/// `benchmarks` package can time internal `setup_builtins` phases; it is not a
/// JavaScript semantic operation.
pub fn profile_setup_builtins_with_realm_state(
  env : Environment,
  output : Array[String],
  realm_state : @runtime.RealmState,
  annex_b? : Bool = false,
) -> Array[(String, Double)] {
  env.realm_state = Some(realm_state)
  let profile = BuiltinSetupProfiler()
  @runtime.with_active_realm_state_unit(realm_state, fn() {
    setup_builtins_with_realm_state_active(
      env,
      output,
      realm_state,
      annex_b,
      profile~,
    )
  })
  profile.timings
}
